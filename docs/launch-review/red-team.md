# Ammo — Adversarial Platform, Privacy & Security Review

Reviewer seat: security reviewer who believes only the code, plus provider
trust-and-safety at Anthropic / OpenAI / Cursor. Not an App Store Guidelines
walkthrough (covered separately).

Fixed constraint accepted as given: the app uses the providers' first-party CLI
OAuth client IDs. Not relitigated below.

Reviewed at commit `557e726` on branch `feat/icon-and-branding`. All line numbers
verified against working-tree files.

---

## Bottom line

**"Your tokens stay in your Keychain, on your device" is TRUE as implemented** —
I traced every write path and found no code that puts an access token, refresh
token, ID token, or session cookie anywhere except an in-memory `OAuthTokens`
value and a Keychain generic-password item, and the Keychain class chosen
(`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `KeychainStore.swift:24`) is
*stricter* than the documentation claims: it never syncs to iCloud Keychain,
never appears in an encrypted iTunes/Finder backup, and does not migrate to a new
device. There are zero third-party packages (`Package.swift`), zero analytics or
crash-reporting egress, no `print()` in shipping code, and every `os.Logger`
interpolation of an error or identifier carries `privacy: .private`. The
App Group container holds four JSON files whose contents I enumerated — none has
a token field. The claim holds. What does *not* hold is the surrounding
documentation: `SPEC.md:18` states the wrong Keychain class and
`SPEC.md:43` states the widget "never touches the network or tokens directly",
which is false — the widget extension process loads tokens from the shared
Keychain group and makes live provider HTTP calls on every timeline refresh
(`Timelines.swift:28`). The most serious code-level defect is not a leak but the
opposite failure mode: a transient file-lock error can cause the app to silently
*destroy* the user's credentials mid-refresh, after the upstream refresh token
has already been rotated, producing unrecoverable sign-out. Ship-blocking items
are a missing `LICENSE` (the entire "audit it yourself" defense is legally
inert without one), the credential-destruction path, and the doc/code mismatches
that a hostile reader will read as the operator's own admission that the trust
model is not what was advertised.

---

## Findings

### BLOCKER-1 — Transient file-lock failure silently deletes the user's credentials

**Evidence:**
- `Apps/iOS/Shared/AccountDeletionStore.swift:29-40`
- `Apps/iOS/Shared/SharedFileLock.swift:15-33`
- `Apps/iOS/Shared/KeychainStore.swift:18`, `:33-36`
- `Apps/iOS/Shared/UsageRefreshCoordinator.swift:126-132`, `:138-145`

`AccountDeletionStore.isDeleted` fails *closed*, by deliberate design:

```swift
} catch {
    AmmoLog.sharedStore.error("Unable to read account tombstones: …")
    return true
}
```

The only way to reach that `catch` is a `SharedFileLock` failure —
`LockError.timedOut` after a 1-second spin at `SharedFileLock.swift:22-31`, or
`LockError.openFailed(errno)`. Both are *reachable in normal operation*: the app,
the widget extension, and a `BGAppRefreshTask` all contend for the same
`deleted-accounts.lock` in the App Group container, and the container is
`NSFileProtectionCompleteUntilFirstUserAuthentication` — an `open(2)` before
first unlock returns `EPERM`, not `EWOULDBLOCK`, which takes the
`throw LockError.openFailed` branch immediately.

`KeychainStore.save` treats that answer as authoritative and *deletes*:

```swift
guard !AccountDeletionStore.isDeleted(id) else {
    delete(for: id)
    throw CancellationError()
}
```

**Impact.** `UsageRefreshCoordinator.swift:126-132` proactively refreshes a token
when it is within 5 minutes of expiry, then calls `KeychainStore.save`. Anthropic
and OpenAI both rotate the refresh token on use. So the sequence is: (1) app
spends the old refresh token, (2) provider issues and invalidates, (3) `save`
hits a lock error, decides the account is deleted, and erases the Keychain item
holding the *new* pair. The user's credentials are now gone from the device and
the old ones are dead upstream. The account silently vanishes with no user action
and no error surfaced — `UsageComponents.swift:309-383` maps everything to
non-technical copy. This is unrecoverable data loss triggered by an ordinary lock
timeout, and it is most likely to fire exactly where contention is highest: a
background refresh racing a widget timeline reload.

**Remediation.** Split the two questions. `isDeleted` should return an
`enum { active, deleted, unknown }`. `unknown` must abort the write (`throw`)
without deleting; only a *positive, successfully read* tombstone may authorize
`delete(for:)`. Additionally, do not call `save` at all when the lock cannot be
acquired — an unwritten new token pair is a recoverable state (re-auth), a
deleted one is not. Raise the lock timeout above 1 s for the save path and
distinguish `EPERM`/`EACCES` (data-protection, retry later) from genuine
contention.

---

### BLOCKER-2 — No `LICENSE` file: the open-source defense does not legally exist

**Evidence:** repository root — no `LICENSE`, `LICENCE`, or `COPYING`
(`find . -maxdepth 2 -iname "LICENSE*"` returns nothing).
`README.md:6` makes the trust claim; nothing grants any rights to verify it.

**Impact.** "It's open source, audit it yourself" is the app's entire answer to
"why should I give this thing my Anthropic refresh token." Without a license the
published source is all-rights-reserved: a security researcher cannot legally
fork it, a distro cannot package it, and — the part that actually matters — a
skeptical user cannot *build it themselves* and compare, because copying the
source to do so is not licensed. The defense is a slogan, not a defense. Provider
trust-and-safety will also read an unlicensed public repo of code that drives
their OAuth clients less charitably than a permissively licensed one.

**Remediation.** Add `LICENSE` (MIT or Apache-2.0; Apache-2.0 additionally gives
you an explicit patent grant and an explicit no-trademark clause, which is worth
having when the repo ships Anthropic/OpenAI/Cursor marks — see NOTE-4). Add the
`SPDX-License-Identifier` header convention if you want it machine-detectable.
State in `README.md` which commit corresponds to which App Store build number so
"audit it yourself" maps to a specific binary (see SHOULD-FIX-6).

---

### BLOCKER-3 — `SPEC.md` states the widget never touches tokens or the network; it does both

**Evidence:**
- Claim: `SPEC.md:43` — `│  touches the network or tokens directly            │`
  (inside the architecture diagram: "reads cached UsageSnapshots via App Group;
  never touches the network or tokens directly")
- Reality: `Apps/iOS/AmmoWidgets/Timelines.swift:28`, `:83`, `:135` — three
  timeline providers each call `UsageRefreshCoordinator.shared.refresh(...)`
- That coordinator reads the Keychain at
  `Apps/iOS/Shared/UsageRefreshCoordinator.swift:101-107` and performs provider
  HTTP at `:126-145`
- The widget target is granted the shared Keychain group and App Group in
  `Apps/iOS/project.yml:83-84`
- The code itself already documents the contradiction:
  `Apps/iOS/AmmoWidgets/AccountIntent.swift:5-8` — "Timeline generation is the
  one widget path that does [read tokens], via UsageRefreshCoordinator and the
  shared Keychain access group"

**Impact.** This is the single most damaging item for the "believe the code, not
the docs" reader, because it is the operator's own specification asserting a
security boundary that the shipping binary does not have. Once one architectural
trust claim is demonstrably false, the reader is entitled to discount
`SPEC.md:17` as well — and that is the paragraph the whole app rests on. The
underlying behaviour is *defensible* (an extension in the same App ID prefix and
keychain access group is the same trust domain as the app, and WidgetKit-driven
refresh is why the widget works at all); the problem is purely that the document
says the opposite. Separately, the widget extension makes network requests in a
process with a much shorter memory/wall-clock budget than the app, so token
refresh can be killed mid-flight there.

**Remediation.** Correct `SPEC.md:39-45` to say the widget extension shares the
Keychain access group and performs its own refresh, and state explicitly that the
app and extension are one trust domain because they share an App ID prefix. Do
not fix this by removing the capability — fix the document. Also correct
`SPEC.md:17-18` and `SPEC.md:445`: the code uses
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not
`kSecAttrAccessibleAfterFirstUnlock`, and there is no "unless you choose
otherwise" — `kSecAttrSynchronizable` is never set, so iCloud Keychain sync is
not offered and not possible.

---

### LIKELY-1 — Pasted desktop credentials sit in a plain `TextEditor`, survive in the app-switcher snapshot, and are never cleared

**Evidence:**
- `Apps/iOS/Ammo/Onboarding/CodexOnboardingView.swift:40-44` —
  `TextEditor(text: $pastedJSON)` with `.autocorrectionDisabled()` and
  `.textInputAutocapitalization(.never)` but no secure entry
- `Apps/iOS/Ammo/Onboarding/CodexOnboardingView.swift:100-122` — `parseAuthJSON`
- `Apps/iOS/Ammo/Onboarding/ClaudeOnboardingView.swift:34-37` — plain `TextField`
  for the Claude authorization code
- No `pastedJSON = ""` after a successful import anywhere in the file
- No `UIApplication` background-snapshot obscuring, and no
  `.privacySensitive()` / `.redacted` on these views

**Impact.** The Codex fallback path asks the user to paste the entire contents of
`~/.codex/auth.json`, which contains a long-lived refresh token. While that view
is on screen:
1. Backgrounding the app causes iOS to write an app-switcher snapshot PNG to
   `Library/SplashBoard/Snapshots` inside the app container, containing the
   rendered refresh token. It is not encrypted beyond normal container
   protection and it *is* included in device backups.
2. The token string remains in `@State` for the lifetime of the sheet after a
   successful import — it is not zeroed, and `String` gives you no control over
   its heap copies anyway.
3. The token traverses the system pasteboard to get there, and on iOS the general
   pasteboard is readable by any foregrounded app and participates in Universal
   Clipboard across the user's own devices.

This is the only credential material that ever exists outside the Keychain, so it
is the sharpest edge of the README claim. The claim survives strictly — the
tokens' *storage* is still Keychain-only — but a hostile reviewer will point at
the snapshot file and say the credential reached disk outside the Keychain, and
they will be right.

**Remediation.** Clear `pastedJSON` (and Claude's `code`) in a `defer` on both
success and failure. Obscure the window on `scenePhase != .active` while an
onboarding sheet is presented — the standard trick is a full-screen cover on
`.inactive`, or mark the sheet `.privacySensitive()` (redaction reason
`.privacy` is applied to snapshots). Consider offering a
`UIPasteControl`-driven paste instead of a text field so the value never renders.
Warn in the footer that the pasteboard copy persists — or better, tell the user
to clear it.

---

### LIKELY-2 — Loopback listener is not torn down when the app is backgrounded mid-flow

**Evidence:**
- `Apps/iOS/Ammo/Onboarding/LoopbackServer.swift:37` — `init(port: UInt16 = 1455, …)`
- `Apps/iOS/Ammo/Onboarding/WebAuth.swift:33-37` — teardown only in a `defer` on
  the awaited flow
- `Apps/iOS/Ammo/AmmoApp.swift:19` — the app reacts to `.active` but nothing
  reacts to `.background` by aborting the flow
- No `scenePhase` observation in `WebAuth.swift`

**Impact.** The Codex flow presents `ASWebAuthenticationSession`, which in the
loopback case (`callbackURLScheme: nil`) leaves the app foregrounded behind a
Safari sheet, so the listener normally lives only for the duration of the
`await`. But if the user hits the home button mid-flow, iOS suspends the process
with the `NWListener` still bound. On resume the listener is in an indeterminate
state and the flow is still awaiting a continuation that may never resume, so the
sheet is stuck and port 1455 stays claimed until the app is killed. This is a
hang/UX defect rather than a credential leak — the code is still validated
against `expectedState` when it does arrive — but "stuck forever on the sign-in
screen" is a plausible App Review outcome and a plausible one-star review.

**Remediation.** Observe `scenePhase` in the flow; on `.background`, call
`server?.stop()` and `abort()` so the continuation resumes with a cancellation.
`WebAuth.swift:77-86` already makes `abort()` double-resume-safe, so this is a
small change.

---

### LIKELY-3 — Nothing detects that another local process already owns port 1455

**Evidence:**
- `Apps/iOS/Ammo/Onboarding/LoopbackServer.swift:41` —
  `parameters.allowLocalEndpointReuse = true`
- `Apps/iOS/Ammo/Onboarding/LoopbackServer.swift:56-58` —
  `var boundPort: UInt16? { listener.port?.rawValue }` — exposed and **never
  read** by `CodexAuthFlow` (`WebAuth.swift:45-47` constructs the server and
  discards the port)
- `Sources/UsageKit/CodexProvider.swift:19` — the redirect URI is the hardcoded
  `http://localhost:1455/auth/callback`

**Impact.** `allowLocalEndpointReuse` sets `SO_REUSEADDR`/`SO_REUSEPORT`
semantics. A second app on the same device that binds :1455 first — the scenario
is another AI-tooling app doing exactly this same CLI-OAuth trick, which is not
hypothetical — can receive the authorization code instead of Ammo, or share
delivery non-deterministically. Ammo never notices, because it never asserts that
it actually got the port it asked for.

Bounding the damage honestly: iOS app sandboxing does *not* prevent one app from
binding a loopback port that another app wants, and there is no OS-level
authentication of loopback peers. What saves this is PKCE — the thief gets a code
but not the `code_verifier` (`Sources/UsageKit/PKCE.swift:12-15`, 64 random bytes
via `SystemRandomNumberGenerator`), so `POST /oauth/token` fails for them. The
realistic outcome is denial-of-sign-in and code disclosure, not account
compromise. That is why this is LIKELY and not BLOCKER. `state` is also 32
CSPRNG bytes and is genuinely enforced — see NOTE-1.

**Remediation.** Read `boundPort` after `init` and fail the flow loudly if it is
not 1455. Consider dropping `allowLocalEndpointReuse` entirely so the bind fails
fast and visibly when the port is taken; the setting exists to survive
`TIME_WAIT` from a previous attempt, which a short retry loop handles just as
well without weakening the exclusivity guarantee.

---

### LIKELY-4 — No privacy manifest in either target

**Evidence:** no `PrivacyInfo.xcprivacy` anywhere in the repo (zero matches); no
`PrivacyInfo.xcprivacy` reference in `Apps/iOS/project.yml`.

**What the code actually needs.** I grepped for every required-reason API family
and the shipping *device* binary uses **none** of them:
- `UserDefaults` — exactly one call site,
  `Apps/iOS/Ammo/Models/AccountStore.swift:153`, inside a private extension
  wrapped in `#if targetEnvironment(simulator)` at `:147` (closed at `:392`).
  Compiled out for device.
- File timestamp (`attributesOfItem`, `.modificationDate`, `resourceValues`) — no
  matches.
- Disk space (`volumeAvailableCapacity*`, `systemFreeSize`, `statfs`) — no matches.
- System boot time (`systemUptime`, `mach_absolute_time`, `kern.boottime`) — no matches.
- Active keyboards (`UITextInputMode.activeInputModes`) — no matches.
- Zero third-party SDKs (`Package.swift` declares no external dependencies), so
  no third-party manifest inherits in.

So a manifest is not *strictly* mandatory. Ship one anyway: an app whose entire
pitch is "audit the privacy story" and that ships no privacy manifest reads badly,
and an empty manifest is the machine-readable form of the README claim. Add this
file to **both** the `Ammo` and `AmmoWidgets` targets (add `- path: Ammo/PrivacyInfo.xcprivacy`
under the app's `sources:` and the equivalent under `AmmoWidgets`, or place it in
`Shared/` — but note `Shared/` is compiled into both targets, and each target
needs its *own* copy at its bundle root, so two files is the safer arrangement):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array/>
</dict>
</plist>
```

Both targets get the identical content, because both are equally empty:
`NSPrivacyCollectedDataTypes` is empty because no data is transmitted to the
developer or any third party — the only network peers are the user's own
providers, which is a user-directed action, not developer collection.

**If you later un-gate the simulator preview code** (or add `@AppStorage`
anywhere), the manifest must gain:

```xml
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array><string>CA92.1</string></array>
        </dict>
    </array>
```

(`CA92.1` = access to user defaults readable and writable only by this app and
apps in the same App Group — which is exactly this app's case.)

**Honest privacy nutrition label answers** (App Store Connect, per data type):
- **Data Not Collected** for every category. The correct answer to "Do you or your
  third-party partners collect data from this app?" is **No**.
- Rationale you can defend line-by-line: usage percentages, plan names, reset
  timestamps, and account labels never leave the device
  (`SharedStore.swift:61`, `UsageHistoryStore.swift:12`,
  `RefreshLedger.swift:31`, `AccountDeletionStore.swift:14` are the complete list
  of persisted files, all in the App Group container). Tokens go only to the
  issuing provider's own token endpoint. There is no analytics, no crash
  reporter, no attribution SDK, no ad identifier.
- Do **not** be tempted to declare "Identifiers → User ID" — the ChatGPT account
  ID (`CodexProvider.swift:129-142`) and the Cursor user ID
  (`CursorProvider.swift:274-283`) are extracted from the provider's own JWT and
  sent back only to that same provider. That is not collection by you.

---

### LIKELY-5 — `SPEC.md` overstates the Keychain guarantee in the user's favour *and* against it

**Evidence:**
- `SPEC.md:17-18` — "`kSecAttrAccessibleAfterFirstUnlock`, non-synchronizable so
  they don't ride iCloud Keychain to other devices unless you choose otherwise"
- `SPEC.md:445` — repeats `kSecAttrAccessibleAfterFirstUnlock`
- `Apps/iOS/Shared/KeychainStore.swift:24` —
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`

**Impact.** Two separate errors in one sentence. First, the actual class is
`…ThisDeviceOnly`, which is *better* for the user: the item is excluded from
encrypted backups and does not migrate on device restore. Second, "unless you
choose otherwise" implies an iCloud-sync opt-in exists. It does not —
`kSecAttrSynchronizable` is never set anywhere in the codebase, and with
`…ThisDeviceOnly` it cannot be. The practical consequence the docs fail to warn
about: **restoring to a new iPhone will silently lose every account and require
re-authenticating all three providers**, because `ThisDeviceOnly` items do not
restore. Users will report this as a bug.

**Remediation.** Fix the two SPEC lines. Add a one-line note to `README.md` that
credentials do not transfer to a new device by design and must be re-added after
a restore. This turns a support burden into a stated feature.

---

### SHOULD-FIX-1 — There is no sign-out that revokes anything upstream

**Evidence:**
- `Apps/iOS/Ammo/Models/AccountStore.swift:65-82` — `remove(_:)`: write tombstone,
  `KeychainStore.delete`, remove from ledger, remove from `SharedStore`
- `Apps/iOS/Shared/KeychainStore.swift:63-71` — deletes the shared-group item and
  the legacy nil-group item
- No `revoke`, `/oauth/revoke`, or logout call exists anywhere: grep for `revoke`
  across `Sources/` and `Apps/` returns nothing

**Impact.** "Remove Account" is *forget locally*, not *sign out*. The refresh
token remains valid at Anthropic / OpenAI / Cursor until it expires on its own
(`SPEC.md:242` notes Anthropic's is roughly a 19-day lifetime). A user who
removes an account because they think the device is compromised has not actually
revoked anything, and the app does not tell them that. Local deletion itself is
thorough — the tombstone at `AccountDeletionStore.swift:14` prevents a racing
in-flight refresh from resurrecting the Keychain item, which is good design.

**Remediation.** Either call the provider's revocation endpoint on removal where
one exists, or — since these are the CLIs' client IDs and a revoke may also kill
the user's desktop CLI session — state plainly in the removal UI that Ammo forgets
the token locally and link the provider's session-management page so the user can
revoke deliberately. Given the imported-token hazard already documented at
`SharedStore.swift:28-31`, the second option is the correct one; silently
revoking a token that the user's desktop CLI is also using would be worse.

---

### SHOULD-FIX-2 — "Remove Account" is destructive, unrecoverable, and unconfirmed

**Evidence:** `Apps/iOS/Ammo/UI/ContentView.swift:270-271` —
`Button("Remove Account", systemImage: "trash", role: .destructive) { store.remove(state.account) }`
with no `.confirmationDialog`.

**Impact.** One mis-tap inside a `Menu` erases the Keychain item, the ledger
entry, and (via `UsageHistoryStore.remove`) up to 90 days of local history, with
no undo and — per SHOULD-FIX-1 — no way to get the token back except a full
re-auth. `role: .destructive` renders it red but does not prompt.

**Remediation.** Add a `.confirmationDialog` naming what is lost (credentials +
history). Cheap, and it is what a reviewer expects of a destructive action.

---

### SHOULD-FIX-3 — Cursor PKCE verifier is sent in a URL query string

**Evidence:**
- `Sources/UsageKit/CursorProvider.swift:91-97` — `pollForTokens(uuid:verifier:)`
  builds `https://api2.cursor.sh/auth/poll?…&verifier=<verifier>`
- `Sources/UsageKit/PKCE.swift:12-15` — the verifier is the 64-byte secret
- `Apps/iOS/Ammo/Onboarding/WebAuth.swift:132`, `:139` — polled up to 600 times
  at 500 ms

**Impact.** This mirrors what the Cursor CLI does, so it is a faithful
implementation rather than an Ammo-invented weakness — but the security property
is worse than the Anthropic/OpenAI flows. A PKCE `code_verifier` in a query
string lands in the provider's HTTP access logs, in any intermediary's logs, and
in `Referer` headers if the endpoint ever redirects. It is repeated up to 600
times per sign-in attempt. TLS protects it in transit, so this is a logging and
server-side-exposure concern, not a network-interception one.

**Remediation.** Nothing you can do unilaterally without breaking compatibility
with Cursor's flow. Document it in `SPEC.md` as a known deviation from RFC 7636
§4.5 (which specifies the verifier in the token request *body*), and reduce the
poll count / add exponential backoff so the secret is transmitted fewer times.
Right now it is a flat 500 ms for 5 minutes.

---

### SHOULD-FIX-4 — Cursor and Claude token flows never verify the returned `state`

**Evidence:**
- `Sources/UsageKit/ClaudeProvider.swift:86-94` — `exchangeCode` sends
  `"state": state` (its own generated value) in the token request; the
  server-echoed state that arrives appended to the pasted code after `#`
  (`ClaudeProvider.swift:85`) is stripped and discarded, never compared
- `Apps/iOS/Ammo/Onboarding/ClaudeOnboardingView.swift:74-75` — passes
  `pkce.state` straight through
- Cursor's flow (`CursorProvider.swift:91`) has no `state` at all — it is
  identified only by a client-generated `uuid`

**Impact.** Modest. For Claude the user manually copies a code out of a browser
page they navigated to themselves, so the classic CSRF-code-injection vector
(attacker-supplied redirect) is not really available; PKCE binds the exchange
regardless. For Cursor the `uuid` plus the verifier serve the same binding role.
The Codex loopback flow, which is the one that genuinely needs `state`, does
enforce it correctly (see NOTE-1). Calling this out because a reviewer reading
`ClaudeProvider.swift:86-94` will notice `state` being *generated and sent* but
never *checked*, which looks like an oversight even where it is not exploitable.

**Remediation.** In `ClaudeOnboardingView`, split the pasted string on `#` and
compare the fragment against `pkce.state` before exchanging, rejecting on
mismatch. Costs three lines and closes the question.

---

### SHOULD-FIX-5 — Reverse-engineered endpoints, one of them never verified against a live account

**Evidence — complete network egress inventory.** Every host and path the binary
can reach, from an exhaustive grep of `https://` and `http://` across `Sources/`
and `Apps/`:

| Host / path | File:line | Status |
|---|---|---|
| `api.anthropic.com/api/oauth/usage` | `ClaudeProvider.swift:10` | Undocumented, reverse-engineered |
| `api.anthropic.com/api/oauth/profile` | `ClaudeProvider.swift:11` | Undocumented, reverse-engineered |
| `platform.claude.com/v1/oauth/token` | `ClaudeProvider.swift:12` | OAuth token endpoint, CLI client ID |
| `claude.ai/oauth/authorize` | `ClaudeProvider.swift:13` | Opened in system browser only |
| `platform.claude.com/oauth/code/callback` | `ClaudeProvider.swift:18` | Redirect target, browser only |
| `chatgpt.com/backend-api/wham/usage` | `CodexProvider.swift:11` | Undocumented, reverse-engineered |
| `auth.openai.com/oauth/token` | `CodexProvider.swift:12` | OAuth token endpoint, CLI client ID |
| `auth.openai.com/oauth/authorize` | `CodexProvider.swift:13` | Opened in system browser only |
| `chatgpt.com/admin/billing` | `CodexWorkspaceBillingPolicy.swift:20` | Opened in system browser only |
| `chatgpt.com/codex/settings/usage` | `CodexWorkspaceBillingPolicy.swift:21` | Opened in system browser only |
| `cursor.com/api/usage-summary` | `CursorProvider.swift:11` | Undocumented; **never verified live** |
| `cursor.com/loginDeepControl` | `CursorProvider.swift:12` | Opened in system browser only |
| `api2.cursor.sh/auth/poll` | `CursorProvider.swift:13` | Undocumented |
| `api2.cursor.sh/oauth/token` | `CursorProvider.swift:14` | Undocumented |

**Nothing else.** No telemetry host, no crash reporter, no analytics, no CDN, no
update check. Transport is `URLSession.shared` only (`Sources/UsageKit/HTTP.swift:14-18`).
Zero external package dependencies (`Package.swift`). I consider "there is
genuinely no telemetry egress" **confirmed**, not inferred.

**Fragility.** `CURSOR_RESEARCH.md:2-9` states in the operator's own words:
"Response *shapes* are cribbed from a maintained third-party (CodexBar, MIT) and
not yet re-verified against a live authenticated response from this account," and
`SPEC.md:339` marks Cursor `LIVE VERIFICATION PENDING`. Shipping a provider
integration to the App Store whose response shape has never been observed from a
real account is a launch-day-bug generator.

The decoding is defensively written — `CodexProvider.swift:173-191` and `:203-220`
use a `flexibleDouble` tolerant decoder, `ClaudeProvider.swift:203-231` falls back
from `limits[]` to `five_hour`/`seven_day` keys — so a shape change is far more
likely to produce a *thrown decode error* (surfaced honestly as a paused-update
notice via `UsageFailureKind`, `UsageComponents.swift:309-383`) than a wrong
number. That is the right failure mode and it is worth saying so explicitly: the
app degrades honestly. The one place it could show a *wrong* number rather than an
error is if a provider changes semantics without changing shape — e.g. reports a
percentage where it previously reported a fraction — and no sanity clamp catches
that. `LimitWindow.remainingPercent` clamps to 0…100
(`Sources/UsageKit/Models.swift:39`), so an out-of-range value silently pins at a
boundary rather than surfacing as suspicious.

**Remediation.** Verify Cursor against a live authenticated account before
submitting, or ship without Cursor and add it in 0.1.1. Add a staleness guard:
if a snapshot's `fetchedAt` is older than some threshold, render it visibly stale
rather than as a current number. Consider surfacing "we could not parse the
provider's response" distinctly from "network failed" so users can report drift.

---

### SHOULD-FIX-6 — "Audit it yourself" is not reproducible from the published tree

**Evidence:**
- `.gitignore:5` — `*.xcodeproj` (the project file is generated, not committed)
- `Apps/iOS/project.yml:1-2` — XcodeGen manifest is the source of truth
- `Apps/iOS/project.yml:19` — `CURRENT_PROJECT_VERSION: 17`,
  `:18` `MARKETING_VERSION: 0.1.0`
- `Apps/iOS/project.yml:9` — `postGenCommand: ./Scripts/fix-local-package-products.sh`

**Impact.** A reader who wants to check that the App Store binary matches the
source has to: install a specific XcodeGen version, run a post-generation shell
script that patches package products, and use a matching Xcode/Swift toolchain.
None of those versions are pinned or recorded. Even ignoring code signing (which
makes bit-for-bit reproduction impossible on iOS regardless), there is currently
no way to establish which commit produced build 17.

**Remediation.** Tag each submitted build (`v0.1.0-build17`) and say in
`README.md` that App Store build *N* is git tag *X*. Pin the XcodeGen version and
required Xcode version in the README. This does not achieve reproducible builds —
you cannot, on iOS — but it converts "trust me" into "here is the exact tree,
diff it."

---

### SHOULD-FIX-7 — Provider terms exposure

Clause-level, distinguishing citation from inference. I have **no network access
in this session**, so I cannot quote live terms verbatim; everything below is
labeled accordingly.

**What the code does that touches this.** The app presents itself as the
providers' own CLIs: `CodexProvider.swift:30` sends `"User-Agent": "codex-cli"`,
`CodexProvider.swift:87-89` uses client ID `app_EMoamEEZ73f0CkXaXp7hrann` with
Codex-specific authorize parameters (`id_token_add_organizations`,
`codex_cli_simplified_flow`), `ClaudeProvider.swift:19` sends
`anthropic-beta: oauth-2025-04-20`, and `CursorProvider.swift:267-272`
reconstructs a `WorkosCursorSessionToken` browser cookie from the OAuth access
token in order to call a dashboard JSON endpoint.

That last one is the weakest position of the three. Everything else is an OAuth
client using a token the user consented to issue; `cookieHeader` is
impersonating a *browser session* against `cursor.com/api/usage-summary`, an
endpoint that exists to serve the web dashboard.

**Anthropic** — *inference, not citation.* Anthropic's Consumer Terms and Usage
Policy have historically prohibited accessing the Services through automated or
non-permitted means and prohibit circumventing rate limits or access controls.
`api.anthropic.com/api/oauth/usage` is not part of the published API surface, so
reading it is automated access to a non-public endpoint. Counterweight: the data
is the user's own account metadata, the token is the user's own, the request rate
is trivial (`RefreshLedger.swift:7` enforces a 60-second minimum fetch interval),
and this is not circumventing a limit — it is *reading* one. Realistic
consequence: nothing in practice for individual users; if Anthropic objects, the
most likely first action is a change to the endpoint or a `User-Agent`/client-ID
check that breaks the app, not account termination. A takedown request against a
public GitHub repo is plausible but not likely at this scale.

**OpenAI** — *inference, not citation.* OpenAI's Terms of Use prohibit
automatically or programmatically extracting data or output, and prohibit
representing that output is human-generated — the first clause is the relevant
one. `chatgpt.com/backend-api/wham/usage` is a ChatGPT web-app internal endpoint.
Sending `User-Agent: codex-cli` (`CodexProvider.swift:30`) is the sharpest fact
here: a T&S reviewer reads a non-Codex client asserting it is Codex as deliberate
misrepresentation of client identity, even though the practical purpose is
compatibility. Realistic consequence: same as Anthropic — endpoint change or
client attestation is the likely response. Account-level action against users is
possible in principle but I have no evidence of it happening for read-only usage
polling.

**Cursor** — *inference, not citation.* Cursor's terms prohibit accessing the
service by automated means and prohibit scraping. The cookie-reconstruction at
`CursorProvider.swift:267-272` is the most defensible-to-attack item in the whole
codebase from a T&S seat, because it is not using an API with a token, it is
synthesizing a browser session credential. Cursor also has the smallest T&S
organization of the three, which cuts both ways: less likely to notice, more
likely to respond bluntly (Cloudflare rule, endpoint change) if they do.

**Your own research notes already anticipate this.** `ANTIGRAVITY_RESEARCH.md:214-227`
contains an explicit "Policy and account risk" section concluding "Do not promise
it in a public binary until the policy interpretation is [resolved]" — for
Antigravity, which is correctly deferred (`UsageRefreshCoordinator.swift:255-262`
returns `nil` for `.antigravity`). Good instinct; the same reasoning applies with
less force to the three shipping providers, and it is to your credit that the
notes say so.

**How to reduce exposure, concretely:**
1. Stop sending `User-Agent: codex-cli`. Send an honest `Ammo/0.1.0` (or leave
   the default). If the endpoint then rejects you, you have learned that OpenAI
   *is* gating on client identity, which is information you want before launch,
   not after. Impersonation converts a gray-area read into an affirmative
   misrepresentation for no functional benefit you have verified.
2. Rate-limit visibly and document it. `RefreshLedger.swift:7-8` (60 s minimum,
   2-minute in-flight lease) is already conservative — say so in the README, it
   is a real mitigating fact.
3. Add a plain-language disclosure in-app and in the README: these are
   unofficial endpoints, they may break, the user's account is subject to the
   providers' terms, and Ammo is not affiliated with or endorsed by Anthropic,
   OpenAI, or Cursor.
4. Have a kill-switch plan. With no backend you cannot remotely disable a
   provider; the best available is that decode failures degrade to a paused
   state, which already works.

---

### NOTE-1 — The loopback OAuth listener itself is sound

I attacked this hard and could not break it beyond LIKELY-2 and LIKELY-3.
Confirmed:
- PKCE S256 correctly implemented — `Sources/UsageKit/PKCE.swift:12-15` (64-byte
  verifier, 32-byte state, `SystemRandomNumberGenerator` at `:28-33`), challenge
  = base64url(SHA256(verifier)) at `:20`, `code_challenge_method=S256` at
  `CodexProvider.swift:87-97`.
- `state` is CSPRNG-generated *and actually enforced*:
  `LoopbackServer.swift:167-184` refuses to return a code unless
  `CodexAuthFlow.isCallbackStateValid` passes (`WebAuth.swift:73-75`), and it
  refuses any path other than `/auth/callback`.
- Non-loopback peers are rejected at `LoopbackServer.swift:44-51` via
  `isLoopback` (`:188-196`), which correctly returns `false` for `.name`
  endpoints and for `@unknown default`; `requiredInterfaceType = .loopback`
  (`:42`) is belt-and-braces on top.
- No response injection: `LoopbackServer.swift:152-156` emits only constant
  `Page` strings; nothing from the query is interpolated into HTML. Test at
  `Apps/iOS/AmmoTests/SignInFlowTests.swift:70-86` specifically proves a hostile
  `error_description` is never rendered.
- Header flood bounded at 16 KiB → `431` (`LoopbackServer.swift:91-98`); request
  line strictly parsed as `GET <target> HTTP/1.x` (`:132-142`).
- Continuations are double-resume-safe: `WebAuth.swift:77-86`, both `@MainActor`,
  both nil the continuation before resuming.
- The "loopback callback races" fix mentioned in git history **is** complete for
  the cases tested: `SignInFlowTests.swift:106-131` binds a real socket end to end
  and proves a rejected callback does not tear down the session, and `:133-153`
  covers fragmented TCP writes. That is unusually good test coverage for this
  layer.

**ATS and local-network permission:** neither is required, and their absence from
`Apps/iOS/Ammo/Info.plist` is correct, not an oversight. ATS governs outbound
`URLSession` loads; the app never issues an HTTP request to localhost — it
*listens*, and the cleartext `http://localhost:1455/…` URL is only ever loaded by
the system browser via `ASWebAuthenticationSession`, which is outside the app's
ATS domain. `NSLocalNetworkUsageDescription` gates unicast connections to *other
devices* on the local network; loopback traffic is exempt, and
`requiredInterfaceType = .loopback` guarantees nothing else is possible.
*(Labeled inference on the loopback exemption — well-founded on Apple's
documented behaviour, but I could not exercise it on a device in this session.)*

### NOTE-2 — App Group container contents are non-sensitive; widget snapshots leak nothing

Complete enumeration of what is written to `group.com.brandon.ammo`:
- `usage-states.json` (`SharedStore.swift:61`) — `StoredAccount` (id, provider,
  user-chosen label, `tokensImported` flag; `SharedStore.swift:23-39` — **no token
  fields**) plus `UsageSnapshot` and a `UsageFailureKind` category
  (`SharedStore.swift:143-151` stores only the category, never the technical error)
- `usage-history.json` (`UsageHistoryStore.swift:12`) — 90 days of downsampled
  percentages
- `refresh-ledger.json` (`RefreshLedger.swift:31`) — timing/backoff state only
- `deleted-accounts.json` (`AccountDeletionStore.swift:14`) — UUIDs
- `codex-billing-balances.json` (`SharedStore.swift:188`) — legacy, actively
  removed by `removeLegacyCodexBillingCache` at `:187-196`
- plus one `.lock` sidecar per store

No credential material crosses the App Group boundary. The widget carries only
rendered values: `AccountIntent.swift`'s `AccountEntity` / `LimitEntity` hold
labels, plan strings, and IDs. Lock-screen `accessoryCircular`
(`WidgetViews.swift:159-186`) renders a gauge percentage and a provider glyph —
a visible-when-locked disclosure of "you have used 80% of your Claude session",
which is exactly what the user asked for and contains no identifier. This area is
clean. The one thing to be aware of: the App Group container is
`NSFileProtectionCompleteUntilFirstUserAuthentication` by default and *is*
included in device backups, so usage history is backed up while the tokens
(`ThisDeviceOnly`) are not. That asymmetry is fine and arguably ideal.

### NOTE-3 — Crash risk on a cold device is low; the three `first!` force unwraps are provably safe

I traced every force unwrap on collection access:
- `Apps/iOS/Ammo/UI/ContentView.swift:218` — `ForEach(snapshot.windowGroups, id: \.first!.id)`
- `Apps/iOS/AmmoWidgets/WidgetViews.swift:111` — `ForEach(compactGroups(snapshot), id: \.first!.id)`
- `Apps/iOS/AmmoWidgets/WidgetViews.swift:570` — `ForEach(detailGroups(snapshot), id: \.first!.id)`

`windowGroups` (`Apps/iOS/Shared/UsageComponents.swift:389-401`) only ever
`append([window])` or appends into an existing group, so no element is ever an
empty array. `compactGroups` (`WidgetViews.swift:137-152`) guards `remaining > 0`
before `group.prefix(remaining)`, so every emitted array has ≥1 element; its
Cursor branch (`:141`) maps each window to a single-element array. `detailGroups`
(`WidgetViews.swift:593-603`) is the same shape. An empty `windows` array yields
an empty `windowGroups`, and `ForEach` over an empty collection is fine. **No
crash reachable here** — but all three would become live crashes the moment
someone edits `windowGroups`, so they are worth replacing with
`id: \.[0].id`-free explicit `Identifiable` wrappers or `enumerated()`.

Other robustness observations, all clean:
- `NWEndpoint.Port(rawValue: port)!` at `LoopbackServer.swift:43` — the only
  caller passes the literal 1455 default (`WebAuth.swift:45`); tests pass 0. Safe,
  but a `!` on a value that in principle comes from configuration.
- JWT decoding (`CodexProvider.swift:129-142`, `CursorProvider.swift:274-283`)
  returns optionals throughout, never traps, and `CursorProvider.swift:274-283`
  allow-lists characters before interpolating the user ID into a cookie header —
  correct injection defense.
- `Sources/UsageKit/HTTP.swift:45-63` uses a tolerant ISO8601 parser rather than a
  single strict formatter.
- Swift 6 strict concurrency is genuinely applied: `UsageRefreshCoordinator` is an
  `actor` (`:46`), `AccountStore` is `@MainActor @Observable` (`:8-10`),
  `MainActor.assumeIsolated` is used only in `presentationAnchor`
  (`WebAuth.swift:88-94`, `:183-189`) where the caller is documented main-thread,
  and `BackgroundRefresh.swift:66-78` uses an `NSLock`-backed `CompletionLatch` to
  guarantee `setTaskCompleted` is called exactly once — the classic
  `BGAppRefreshTask` termination bug is correctly handled.
- `nonisolated(unsafe) let task = task` at `BackgroundRefresh.swift:20` is the one
  concurrency escape hatch; it is confined to a single closure capture of a
  `BGTask`, which is the standard workaround, and the latch makes it safe.

### NOTE-4 — Repo hygiene before publishing

- `DEVELOPMENT_TEAM: JN24JD42L3` at `Apps/iOS/project.yml:21` is your Apple Team
  ID. It is not a secret — it appears in every provisioning profile and in the
  signed binary — but it does link the repo to your Apple Developer identity, and
  it makes the tree non-buildable for anyone else without editing. Move it to a
  local `.xcconfig` that is gitignored, or accept it and say so.
- No secrets found. A scan for `sk-ant-`, `sk-proj-`, `-----BEGIN`,
  `password=`/`api_key=`, and personal email addresses across all tracked
  `.swift`/`.md`/`.yml`/`.plist`/`.json`/`.sh` files returned only two hits, both
  benign documentation placeholders: `SPEC.md:170` (`sk-ant-oat01-…`) and
  `SPEC.md:242` (`sk-ant-ort01-…`). No real credential is committed.
- `.DS_Store` exists in the working tree at the repo root but is correctly
  gitignored (`.gitignore:6`) and **not tracked** (`git ls-files` confirms).
  `.build/`, `.swiftpm/`, `xcuserdata/`, and `*.xcodeproj` are likewise ignored.
- `SPEC.md:409-421` documents re-derivation methodology including `mitmproxy` and
  `ANTHROPIC_LOG=debug`. Factually it is just "here is how I learned the contract,"
  and publishing it is defensible as good-faith transparency — but a provider
  T&S reader lands on "I intercepted your CLI's TLS traffic to reverse the
  endpoint" and it reads as an admission rather than a methodology note. Consider
  moving the re-derivation section to a separate `docs/` file with framing that
  makes the intent (maintainability when the contract drifts) explicit, rather
  than leaving it inline in the top-level spec.
- `CURSOR_RESEARCH.md` and `ANTIGRAVITY_RESEARCH.md` are, on the whole, credits
  rather than liabilities — they are honest, they label uncertainty, and
  `ANTIGRAVITY_RESEARCH.md:214-227` explicitly declines to ship something on
  policy-risk grounds. Two things read badly in public: `CURSOR_RESEARCH.md:2-9`
  admitting the shipping Cursor contract is "cribbed from a maintained
  third-party (CodexBar, MIT) and not yet re-verified" (fix the underlying fact,
  not the sentence — see SHOULD-FIX-5), and the general framing of both documents
  as "how to get at private APIs," which is accurate but is the paragraph a
  journalist would quote. Neither contains a secret or a personal identifier.
- Third-party marks: the app renders Anthropic/OpenAI/Cursor logos
  (`Apps/iOS/Shared/ProviderLogo.swift`). Trademark use for nominative
  identification is generally fine; a `NOTICE`/README line disclaiming
  affiliation and attributing marks to their owners costs nothing and removes an
  easy complaint. Also credit CodexBar (MIT) explicitly if any of its contract
  knowledge is embodied in the decoders — `CURSOR_RESEARCH.md:6-9` says it is.

### NOTE-5 — Minor items, one line each

- `Package.swift` declares `platforms: [.iOS(.v17), .macOS(.v14)]` while
  `Apps/iOS/project.yml:7` targets iOS 18.0 — harmless mismatch, but it means
  `UsageKit` compiles against an availability floor the app never uses.
- `WebAuth.swift:62` and `:156` set
  `prefersEphemeralWebBrowserSession = false`, which is the right call (it lets
  the user reuse an existing provider session) but does mean the auth cookie jar
  is shared with Safari — worth one sentence in the README since it is a
  deliberate privacy trade.
- `Sources/UsageKit/Models.swift:268` includes `body.prefix(300)` in
  `UsageError`'s description. That string is only ever logged with
  `privacy: .private` (`UsageRefreshCoordinator.swift:221`) and is never shown to
  the user (`UsageComponents.swift:309-383` maps to fixed copy), so no response
  body reaches a log in the clear — but if anyone ever logs a `UsageError` with
  `.public`, up to 300 bytes of a provider response body goes to the unified log.
  Worth a comment at the definition site.
- Account `label` is free text typed by the user
  (`AccountStore.swift:53-56`) and stored in the App Group container in cleartext.
  If a user types their email as the label, that email is now in a backed-up
  plaintext JSON file. Not a defect, worth knowing.
- `ITSAppUsesNonExemptEncryption: false` (`Apps/iOS/project.yml:49`) is correct
  here — the app uses only HTTPS and platform crypto, which is exempt.

---

## What I could not verify statically

- **Runtime Keychain behaviour.** I read the `kSecAttrAccessible` value in source;
  I did not dump the item's attributes on a device. Confirming the item is truly
  `ThisDeviceOnly`, non-synchronizable, and absent from an encrypted backup needs
  a device and a backup inspection.
- **Whether the App Group container files are readable before first unlock**, and
  therefore how often BLOCKER-1's `openFailed` branch actually fires in the
  field. This needs instrumentation on a locked device with a background refresh
  scheduled.
- **App-switcher snapshot contents** (LIKELY-1). Confirming the pasted refresh
  token is legible in `Library/SplashBoard/Snapshots` requires backgrounding the
  app on a device with the onboarding sheet up and inspecting the container.
- **Loopback port contention** (LIKELY-3). Whether iOS actually permits a second
  app to bind :1455 with `SO_REUSEPORT` semantics, and which process wins
  delivery, needs two apps on one device.
- **Local-network permission prompt.** I am confident loopback is exempt, but I
  did not observe a first-run of the Codex flow on a device to confirm no prompt
  appears.
- **The Cursor contract end to end.** `cursor.com/api/usage-summary`,
  `api2.cursor.sh/auth/poll`, and `api2.cursor.sh/oauth/token` were never
  exercised against a live authenticated account, by the operator's own admission
  (`CURSOR_RESEARCH.md:2-9`, `SPEC.md:339`). I could not do so either — no
  network access, no account.
- **Whether the Anthropic and OpenAI usage endpoints still return the shapes
  documented at `SPEC.md:157-162`.** The dates on those contracts are the only
  evidence; the shapes could have drifted since.
- **Provider terms of service, verbatim.** No network access. SHOULD-FIX-7 is
  labeled inference throughout and should be re-checked against the current
  published terms before you rely on any of it.
- **`swift test` was not run** in this session. The test files were read and the
  assertions verified by inspection; I did not execute them.
- **Xcode/App Store upload validation.** Whether the archive uploads clean
  without a `PrivacyInfo.xcprivacy` (LIKELY-4) can only be established by
  attempting the upload.

---

**Review complete.**
