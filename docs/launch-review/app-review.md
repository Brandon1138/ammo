# Ammo — Adversarial App Store Readiness Review

**Build under review:** `com.brandon.ammo` 0.1.0 (17) · iPhone-only, portrait, iOS 18.0+
**Reviewer seat:** Apple App Review, no Claude / ChatGPT / Cursor account.
**Repo state at review:** branch `feat/icon-and-branding`, HEAD `557e726`, working tree clean.

---

## Bottom line

**Do not submit as-is.** The binary is in good shape — no private APIs, correct background-task
plumbing, an honest export-compliance declaration, real error taxonomy, working Dynamic Type — but
the *submission* is not assemblable today. Three things decide the outcome, in order:

1. **A reviewer with no provider account sees an empty screen with three buttons that all dead-end
   at a third-party login wall.** There is demo data in the codebase, but it is compiled out on
   device (`Apps/iOS/Ammo/Models/AccountStore.swift:148`). This is a near-certain 2.1 rejection and
   it is also the cheapest fix in this document.
2. **Zero App Store Connect metadata exists in this repo, and two mandatory submission fields
   (privacy policy URL, App Privacy nutrition label) have no source of truth anywhere.** You cannot
   press Submit without them.
3. **The vendor logos are pixel-extracted from the providers' own shipping app icons**
   (`Apps/iOS/Scripts/extract-provider-glyphs.py:2`, `Apps/iOS/Assets/Official/`). That is the
   weakest 5.2.5 surface in the app, and it is the thing most likely to convert the (expected,
   defensible) 5.2.2 conversation into a losing one.

The OAuth-client-ID design is out of scope per instruction; §"Predicted 5.2.2 fight" below prepares
the defense rather than reopening it.

---

## BLOCKER findings

### B1 — App Review cannot evaluate the app at all

**Severity:** BLOCKER
**Guideline:** 2.1 Performance — App Completeness. *"If your app requires… a login, provide a demo
account… If your app… includes account-based features, include a demo mode or sample data."*

**Evidence**

- `Apps/iOS/Ammo/UI/ContentView.swift:177-187` — the entire signed-out experience:
  `ContentUnavailableView` "No accounts yet" + three buttons (`Add Claude`, `Add Codex`,
  `Add Cursor`).
- `Apps/iOS/Ammo/UI/ContentView.swift:166-173` — each button presents an onboarding sheet whose only
  path forward is a third-party sign-in.
  - Claude: `Apps/iOS/Ammo/Onboarding/ClaudeOnboardingView.swift:22-38` — user must sign in at
    `claude.ai`, copy a code, paste it back.
  - Codex: `Apps/iOS/Ammo/Onboarding/CodexOnboardingView.swift:29` — `ASWebAuthenticationSession`
    against `auth.openai.com`.
  - Cursor: `Apps/iOS/Ammo/Onboarding/CursorOnboardingView.swift:26` — browser approval + poll.
- `Apps/iOS/Ammo/Models/AccountStore.swift:148` — `#if targetEnvironment(simulator)`. The complete,
  well-built demo fixtures at `AccountStore.swift:173-390` (three accounts, 84 days of history,
  on-demand pools in four scopes) **do not exist in a device build**, which is what App Review runs.
- `Apps/iOS/Ammo/UI/ContentView.swift:40-55` and `:90-95` — the preview launch arguments and the
  `ammo://preview-history` entry point are simulator-gated too.
- Reviewer's view confirmed by `Screenshots/ammo-simulator-empty-debug.jpg`.
- Widgets are equally opaque: `Apps/iOS/AmmoWidgets/WidgetViews.swift:31-40` renders
  `"Set up in Ammo"` when no account exists.

**What the reviewer would say**

> Guideline 2.1 - Information Needed
> We were unable to review your app because we could not sign in. The sign-in screens require an
> account with a third-party service that we do not have access to. Please provide a demo account,
> or a demo mode that allows the app's features to be reviewed without an account.

**Remediation — the three options, honestly ranked**

| Option | Viable? | Why |
|---|---|---|
| Demo account in the Review Notes | **No** | You cannot mint an Anthropic / OpenAI / Cursor account for Apple. Handing over your own credentials exposes your inference quota, gives App Review a token that can bill your account, and is very likely a provider ToS violation. Do not do this. |
| **Demo / sample-data mode in the shipped build** | **Yes — do this** | The fixtures already exist and are already the right shape. |
| Screenshots + a written walkthrough only | Insufficient alone | App Review will still launch the app. Fine as a *supplement*. |

Concrete fix (smallest change that closes this):

1. Move `AccountStore.historyPreviewStates` / `historyPreviewSamples`
   (`Apps/iOS/Ammo/Models/AccountStore.swift:213-390`) out of the `#if targetEnvironment(simulator)`
   block into an always-compiled `DemoData` type.
2. Add a persisted `isDemoMode` flag (`@AppStorage` / App Group) that `AccountStore` consults
   alongside `SharedStore.load()` at `AccountStore.swift:35`.
3. Add a fourth, visible action to the empty state at `ContentView.swift:182-186`:
   `Button("See a demo") { store.enableDemoMode() }`, and a matching "Exit demo" affordance in the
   Usage toolbar so it is never a trap.
4. Label it unambiguously in-app — a `Text("Sample data")` badge in the section header — so it is not
   a hidden feature under **2.3.1** and cannot be read as fabricated real data.
5. Keep demo mode fully offline: `AccountStore.refresh(ids:reason:)` must early-return
   (mirroring the existing guard at `AccountStore.swift:93-95`).
6. State it in the Review Notes (draft below).

This also makes the widgets reviewable, since `SharedStore` is the widget's only input
(`Apps/iOS/AmmoWidgets/AccountIntent.swift:33-44`).

---

### B2 — Privacy policy URL: mandatory, does not exist

**Severity:** BLOCKER
**Guideline:** 5.1.1 Privacy — Data Collection and Storage (and App Store Connect: *App Privacy →
Privacy Policy URL* is a required field for every app; you cannot submit without it).

**Evidence:** no privacy policy, no support page, no `docs/` site, no URL anywhere in the repo.
`git` shows no `fastlane/`, no `metadata/`. The app has no in-app privacy link either
(`Apps/iOS/Ammo/UI/ContentView.swift` has no Settings/About surface at all).

**What the reviewer would say** — this one never reaches a human; App Store Connect blocks the
submission form.

**Remediation.** Publish a one-page policy (GitHub Pages off the public repo is fine) that says
exactly what the code does, and nothing more:

- Ammo has no server and no developer-operated backend. Verify:
  `Sources/UsageKit/HTTP.swift:11-19` — every request goes through `URLSession` directly to the
  provider host named in `ClaudeProvider.swift:10-13`, `CodexProvider.swift:11-13`,
  `CursorProvider.swift:11-14`. There is no other host in the binary.
- Credentials are stored only in the iOS Keychain, device-local, non-syncing:
  `Apps/iOS/Shared/KeychainStore.swift:24` — `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- Usage snapshots are stored only in the App Group container:
  `Apps/iOS/Shared/SharedStore.swift:60-62`.
- No analytics, no crash reporting, no advertising identifier, no third-party SDK. Verify:
  `Package.swift:11-15` — zero external dependencies.
- Deleting an account erases its Keychain item, cache, and history:
  `Apps/iOS/Ammo/Models/AccountStore.swift:65-82`, `Apps/iOS/Shared/SharedStore.swift:96-105`.
- Uninstalling the app removes everything.

---

### B3 — App Privacy nutrition label has no source of truth

**Severity:** BLOCKER
**Guideline:** 5.1.1(i) — *"you must provide… a clear, accessible privacy policy"* + App Store
Connect App Privacy questionnaire (required to submit).

**Evidence:** no `PrivacyInfo.xcprivacy` in the repository (`find . -name "*.xcprivacy"` → 0 files),
and no metadata directory. Nothing in the repo answers the questionnaire.

**Remediation — the exact answers to give.** Based on a full read of the network and persistence
paths, the correct answer is **Data Not Collected** for every category. "Collect" in Apple's
definition means transmitting data off-device in a way that makes it accessible to you or your
partners for longer than servicing the request. Ammo transmits only to the user's own provider, at
the user's direction, with the user's own credentials, and retains nothing off-device.

Answer set:

- **Do you or your third-party partners collect data from this app?** → **No.**
- Result: the listing shows *Data Not Collected*. No further sub-questions.

Do **not** be tempted to declare "Contact Info → User ID" for the OAuth account ID
(`Sources/UsageKit/Models.swift`, `OAuthTokens.accountID`); it never leaves the device
(`Apps/iOS/Shared/KeychainStore.swift:17-37`), so declaring it would be *inaccurate* in the other
direction and invites 5.1.1 questions you don't need.

Adjacent App Store Connect answers you must also get right:

- **Export compliance → Uses encryption?** Answer consistent with `ITSAppUsesNonExemptEncryption`
  = `false` (`Apps/iOS/Ammo/Info.plist:40-41`). See §S1 — the declaration is correct.
- **Content Rights → Does your app contain, show, or access third-party content?** → **Yes**, and
  you must assert you have the rights. See §L1 and the Review Notes draft.
- **Age rating** → 4+. Nothing in the app triggers a higher tier; the "Ammo"/bullet motif is
  abstract (see §N4).

---

### B4 — The entire metadata surface is unwritten

**Severity:** BLOCKER (cannot submit)
**Guideline:** 2.3 Performance — Accurate Metadata; 2.3.7 (name/subtitle); 2.3.1 (hidden features).

**Evidence:** the repo contains no `fastlane/`, no `metadata/`, no `.itmsp`, no store copy. The only
descriptive prose is `README.md` and `PRODUCT.md`, and both contain claims that would be problems if
pasted into the listing (§B5).

**Remediation — field by field.**

| Field | Must contain | Must avoid |
|---|---|---|
| **App Name** (30) | `Ammo` — clean under 4.1 and 2.3.7; unique, no provider mark. | Any provider name in the *name*. `Ammo for Claude`, `Claude Usage`, `Codex Meter` all invite 5.2.5 / 2.3.7. |
| **Subtitle** (30) | What it is, generically: `AI coding usage, at a glance`. | Provider trademarks. Subtitle is treated as name-adjacent by App Review. |
| **Promotional text** (170) | Current-build facts only. `Included limits, reset times, and on-demand balances — on your Home Screen and Lock Screen.` | "Coming soon", "Antigravity support planned", version-teasers (2.3.1/2.3). |
| **Description** (4000) | Feature list matching the shipping build: three tabs (Usage / On-demand / History), three widget families incl. Lock Screen circular, background refresh, on-device-only storage. One explicit paragraph: *"Ammo is an independent app. It is not affiliated with, endorsed by, or sponsored by Anthropic, OpenAI, or Anysphere. Claude, Codex, ChatGPT, and Cursor are trademarks of their respective owners. Ammo requires you to sign in to your own existing account with each service."* | Every phrase in §B5. Also avoid the word "unlimited", any pricing claim about the *providers*, and any implication Ammo grants or extends allowance. |
| **Keywords** (100) | Generic: `usage,quota,limits,tokens,developer,coding,widget,rate limit,allowance,meter`. | `claude`, `anthropic`, `openai`, `chatgpt`, `codex`, `cursor`, `anysphere`. Third-party trademarks in keywords are a standard 5.2.5 rejection and buy you nothing that the description doesn't. |
| **Support URL** | Required. A real page with a working contact route — a GitHub Issues URL on the public repo is acceptable and is *stronger* here than a mailto, because it doubles as the open-source evidence. | A 404, a link to the repo root with issues disabled, or a bare mailto. |
| **Privacy Policy URL** | Required. See §B2. | — |
| **Screenshots** | 6.9" and 6.5" (or current required sets). Use the real device captures you already have — `Screenshots/ammo-device-final-build13-loaded.png`, `…-widget.png`, `…-build13-dark.png`. | Device frames with a different device's bezel, or any screenshot showing a state the demo build can't produce. |
| **Review Notes** | See the drafted text at the end of this document. | Leaving it blank. Blank Review Notes on *this* app is a self-inflicted rejection. |

Naming provider trademarks in the **description body** (as referential/nominative use, with the
disclaimer above) is normal and generally accepted. Naming them in **name / subtitle / keywords** is
where apps get rejected.

---

## LIKELY findings

### L1 — Vendor logos are extracted from the providers' shipping app icons

**Severity:** LIKELY
**Guideline:** 5.2.5 Legal — Intellectual Property — *"Apps should not… use protected third-party
material such as trademarks, copyrighted works… without permission."* Secondary exposure: 4.1
Copycats.

**Evidence**

- `Apps/iOS/Shared/ProviderAssets.xcassets/` bundles seven imagesets: `logo-claude`, `logo-codex`,
  `logo-codex-menu`, `logo-cursor`, `logo-cursor-menu`, `logo-cursor-monochrome`,
  `logo-openai-monochrome`.
- `Apps/iOS/Scripts/extract-provider-glyphs.py:2` — docstring: *"Remove app-icon tiles while
  preserving the official provider glyph pixels."*
- `Apps/iOS/Scripts/extract-provider-glyphs.py:12-13` — source directory `Assets/Official`,
  destination `Shared/ProviderAssets.xcassets`.
- `Apps/iOS/Assets/Official/cursor-app-icon.png`, `Apps/iOS/Assets/Official/codex-app-icon.png` —
  the third-party **app icons** are checked into this repository as build inputs.
- `Apps/iOS/Shared/ProviderLogo.swift:5-6` — the code comment states the intent plainly:
  *"Official provider artwork. …if a first-party asset is missing, that is a build defect."*
- Rendered at `Apps/iOS/Ammo/UI/ContentView.swift:140/149/158` (add-account menu) and `:255`
  (section headers); in widgets at `Apps/iOS/AmmoWidgets/WidgetViews.swift:196`.

**What the reviewer would say**

> Guideline 5.2.5 - Legal - Intellectual Property
> Your app includes images or other content that may be protected by intellectual property rights.
> Specifically, your app displays the Cursor and OpenAI logos. Please provide documentary evidence of
> your rights to use this content, or remove it.

**Assessment.** Displaying a provider's mark next to that provider's own data, to identify which
account a row belongs to, is textbook nominative/referential use, and the app does not imply
affiliation: the icon is original (§4.1 below), the name is original, and no marketing surface claims
endorsement. That is a good position. What weakens it materially is the *provenance*: the artwork was
pixel-lifted from the providers' shipping app icons, not from a published brand kit under its
brand-guidelines license. An app icon is the strongest trademark artifact a company has, and
"extracted from their icon" is a bad sentence to have to say to App Review or to a provider's legal
team (see also §N5, 5.6).

**Remediation, in order of preference — none of these gut the design:**

1. **Re-source, don't redraw.** Replace each asset with the vendor's own published brand asset:
   Anthropic's press/brand kit, OpenAI's brand guidelines assets, Cursor's brand page. Keep the same
   optical sizing already tuned in `ProviderLogo.swift:39-45`. Record the source URL and the
   permitted-use clause per asset in a `Apps/iOS/Shared/ProviderAssets.xcassets/SOURCES.md`. This
   changes ~nothing visually and converts "extracted" into "used per their published guidelines."
2. **Delete `Apps/iOS/Assets/Official/` from the repo and from git history going forward**, and drop
   `extract-provider-glyphs.py`. Shipping a competitor's app icon PNG as a build input is the single
   most quotable artifact in this repository.
3. **Add the in-app disclaimer.** There is currently no "not affiliated" statement anywhere in the
   binary (`grep -ri "not affiliated"` → 0 hits). Add one line to a Settings/About row, or to the
   empty state at `ContentView.swift:180-181`. This is cheap and it is the thing Apple points at when
   deciding whether an app "implies endorsement".
4. **Have a fallback.** `ProviderLogo.swift:27-32` currently renders *nothing* for Claude/Codex/Cursor
   if an asset is missing (`fallbackSymbolName` is `nil` for all three, `:87`). If you are ever forced
   to pull an asset in a hurry, you want a monogram or SF Symbol fallback already in place rather than
   an invisible header.

**App icon — clean.** `Apps/iOS/Ammo/AppIcon.icon/Assets/Vector.png` is an original abstract "A"
monogram with a bullet-shaped cut; `Vector 3.png` is a blue bullet form. No provider mark, no
resemblance to Claude/Codex/Cursor iconography. `Apps/iOS/Ammo/AppIcon.icon/icon.json:2-10` supplies
light/dark/tinted specializations correctly. Nothing here draws 4.1.

---

### L2 — App icon may not make it into the binary

**Severity:** LIKELY (promote to BLOCKER if the verification below fails — it is an upload-time
rejection, not a review-time one)
**Guideline:** App Store Connect binary validation (ITMS-90022 / ITMS-90713, "Missing app icon"), and
2.3 for a listing whose icon does not match.

**Evidence**

- `Apps/iOS/Ammo/Assets.xcassets/AppIcon.appiconset/Contents.json:3` declares a slot —
  `{ "idiom": "universal", "platform": "ios", "size": "1024x1024" }` — with **no `filename` key**, and
  the directory contains only `Contents.json`. The appiconset is empty.
- `Apps/iOS/project.yml:59` sets `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`, which names that
  empty set.
- The real artwork lives in a *sibling* Icon Composer bundle, `Apps/iOS/Ammo/AppIcon.icon/`, which
  the generated project picks up as a resource:
  `Apps/iOS/Ammo.xcodeproj/project.pbxproj:119` — `lastKnownFileType = wrapper.icon` — and
  `:433` — `AppIcon.icon in Resources`.

So two things both named `AppIcon` are in play, one of them empty. Xcode 26 resolves this in favour of
the `.icon` bundle, which is presumably why build 17 looks right on your device — but this is exactly
the configuration that produces a silent no-icon archive when the toolchain, the `xcodegen` version,
or the CI Xcode differs from your local one.

**What the reviewer would say** — nothing; App Store Connect rejects the upload before a human sees
it: *"Missing Info.plist value. A value for the key 'CFBundleIconName' … is missing"* /
*"The app bundle does not contain an app icon for iPhone of exactly '1024x1024' pixels."*

**Remediation.** Verify before you waste a submission:

```sh
cd Apps/iOS && xcodegen
xcodebuild -project Ammo.xcodeproj -scheme Ammo -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/Ammo.xcarchive archive
plutil -p /tmp/Ammo.xcarchive/Products/Applications/Ammo.app/Info.plist | grep -i icon
ls /tmp/Ammo.xcarchive/Products/Applications/Ammo.app/AppIcon*
```

You want `CFBundleIconName = AppIcon` present and `AppIcon60x60@2x.png` / `AppIcon76x76@2x~ipad.png`
emitted. If they are missing, delete the empty `Apps/iOS/Ammo/Assets.xcassets/AppIcon.appiconset/`
entirely so only the `.icon` bundle claims the name.

---

### L3 — Recovering from an expired token requires deleting the account

**Severity:** LIKELY
**Guideline:** 2.1 App Completeness (a core flow that dead-ends), with 4.2 Minimum Functionality as
the fallback framing.

**Evidence**

- `Apps/iOS/Shared/UsageComponents.swift:351` — the entire remedy offered for an authentication
  failure: `"Remove and add this \(providerName) account again to resume updates."`
- `Apps/iOS/Shared/UsageComponents.swift:324` — `.authentication` is excluded from
  `canRetryImmediately`, so the notice renders **with no action button at all**
  (`:272-282`, `:291-294`).
- The only action in the per-account menu is destructive:
  `Apps/iOS/Ammo/UI/ContentView.swift:269-275` — a single `Button("Remove Account", role: .destructive)`.
- This is a reachable state, not theoretical: `Apps/iOS/Shared/UsageRefreshCoordinator.swift:163-171`
  reaches it whenever an *imported* Codex token expires, and
  `Apps/iOS/Ammo/Onboarding/CodexOnboardingView.swift:50` tells users up front that imported tokens
  will expire and are never refreshed.

**What the reviewer would say**

> Guideline 2.1 - Performance - App Completeness
> The app displayed an error indicating the account needed attention, but no way to re-authenticate
> was provided. Please review and resolve.

**Remediation.** Add a `Re-authenticate` action to the account menu at `ContentView.swift:269-275`
that reopens the provider's onboarding sheet and updates the existing account's Keychain item in
place, rather than creating a new `StoredAccount`. Then make `.authentication` actionable in
`UsageComponents.swift:321-326` with `actionTitle` = `"Sign In Again"` wired to that sheet. This also
fixes the widget dead-end, since `WidgetViews.swift:236` currently just says "open Ammo".

---

### L4 — Repo prose is the wrong raw material for the store listing

**Severity:** LIKELY (if reused verbatim)
**Guideline:** 2.3 Accurate Metadata; 2.3.1 (features not present in the build).

**Evidence — the specific sentences that must not survive into metadata:**

- `README.md:6-7` — *"No server. No stranger's OAuth app. Your tokens stay in your Keychain, on your
  device, in an app you built."* The last clause is false for an App Store user: *they* did not build
  it, you did — which is exactly the trust claim the sentence is trading on. Under 2.3 that reads as a
  misleading claim about the shipped product.
- `README.md:3-4` — *"Antigravity planned."* Unshipped features in metadata → 2.3 / 2.3.1. Antigravity
  is in the enum (`Sources/UsageKit/Models.swift:9`) but has no add path
  (`ContentView.swift:171` → `EmptyView()`) and no provider (`UsageRefreshCoordinator.swift:260` →
  `nil`). Correctly invisible in the app; keep it invisible in the listing.
- `README.md:19` — *"macOS menu bar app (stretch)"* — roadmap item, same problem.
- `README.md:9-11` — *"This repo doubles as a DIY kit… so you never have to trust anyone else's
  binary with your accounts."* Read literally, this is the developer telling users not to trust the
  binary he is asking them to install. Do not put it in the description.
- `SPEC.md:10` and `SPEC.md:343` — *"reverse-engineered API contracts"*, *"the full reverse-engineered
  contract"*. See §N5 — this matters because you will be linking this repo in the Review Notes.
- `Sources/UsageKit/CursorProvider.swift:6-7` — *"reads the same private dashboard summary used by
  Cursor's own web UI"*. Accurate, and fine as a code comment; quotable against you if a reviewer
  browses the linked repo.
- `SPEC.md:160-161` — *"These are undocumented APIs and may drift."* An honest engineering note that a
  reviewer would read as an admission of instability under 2.1.

**Remediation.** Write the description from the shipping feature set, not from the README. Then, before
linking the repo in Review Notes, neutralize the three provocative phrases above — *"contracts
documented from the providers' own authenticated endpoints, as observed from a signed-in account"*
carries the same information without the word that triggers the argument. Add a `LICENSE` file; there
is none today (`ls LICENSE*` → no matches), and "we're open source" is a weaker claim without one.

---

## SHOULD-FIX findings

### S1 — 2.5 Software Requirements: audited, and mostly clean

**Severity:** SHOULD-FIX (one item), otherwise clean
**Guideline:** 2.5.1 (private APIs), 2.5.2, 2.5.4 (background modes)

Item by item, so you know what was actually checked:

- **Private / undocumented Apple API — none found.** The app links only `SwiftUI`, `WidgetKit`,
  `AppIntents`, `BackgroundTasks`, `AuthenticationServices`, `SafariServices`, `Network`, `Security`,
  `StoreKit`, `CryptoKit`, `Darwin`, `Foundation`. The lowest-level call in the app is
  `Darwin.open(… O_CREAT|O_RDWR|O_EXLOCK|O_NONBLOCK …)` at
  `Apps/iOS/Shared/SharedFileLock.swift:19-21` — public POSIX, not a private API, not a required-reason
  API. **Clean under 2.5.1.**
- **`UIBackgroundModes: fetch` + `BGTaskSchedulerPermittedIdentifiers` — justified and correctly
  implemented.** `Apps/iOS/Ammo/Info.plist:42-45` and `:7-10`;
  `Apps/iOS/project.yml:47-48`. Registration happens before launch completes
  (`Apps/iOS/Ammo/AmmoApp.swift:7-9` — in `App.init`, which is the correct window), scheduling happens
  on background transition (`AmmoApp.swift:20-21`), the task re-arms *before* provider work
  (`Apps/iOS/Ammo/Services/BackgroundRefresh.swift:24`), `setTaskCompleted` is called exactly once via
  a lock (`BackgroundRefresh.swift:66-78`), the expiration handler cancels the work and reports
  failure honestly (`BackgroundRefresh.swift:34-39`), and success is reported truthfully rather than
  unconditionally (`BackgroundRefresh.swift:45-53`). Background refresh is the app's entire premise —
  a usage meter that is stale on the Home Screen is not the product. **Clean under 2.5.4.**
- **`ammo://` URL scheme — validated, not an injection surface.** `Apps/iOS/Ammo/Info.plist:27-37`;
  parsing at `Apps/iOS/Shared/HistoryLink.swift:25-35` requires `scheme == "ammo"`, `host == "history"`,
  and a well-formed `UUID`, returning `nil` otherwise. The handler at
  `Apps/iOS/Ammo/UI/ContentView.swift:96-102` only navigates. The `preview-history` branch that
  installs fake data is compile-gated to the simulator (`ContentView.swift:90-95`) — verify this stays
  gated if you implement §B1's demo mode, or it becomes a hidden feature under 2.3.1. **Clean.**
  *Minor:* `ammo` is a generic, unclaimable scheme; any other app can register it. Not a rejection,
  but a Universal Link would be more robust if you ever expose deep links publicly.
- **Loopback HTTP listener — the one SHOULD-FIX.** `Apps/iOS/Ammo/Onboarding/LoopbackServer.swift:37-53`
  binds TCP `1455`. It is correctly constrained: `requiredInterfaceType = .loopback` (`:42`), an
  explicit non-loopback peer rejection (`:45-48`, `:188-196`), a 16 KiB header cap (`:14`, `:91-98`),
  GET-only request-line validation (`:132-142`), `state` matched before a code is accepted
  (`:177-183`, cross-checked at `Onboarding/WebAuth.swift:73-75`), and no interpolation of
  callback-supplied text into the served HTML (`:20-26`, `:152-156`). It is torn down in the `defer` at
  `WebAuth.swift:33-37`. **No `NSLocalNetworkUsageDescription` is required** — loopback is exempt from
  the local-network privacy prompt, and the listener never browses or advertises Bonjour. The gap:
  the port is hard-coded with no fallback (`LoopbackServer.swift:37`), so if `1455` is unavailable
  `NWListener` throws and Codex sign-in fails with a generic error
  (`WebAuth.swift:47-51`). Low probability on iOS, but if it happens *during review* it looks like a
  broken feature. Add a second candidate port, or surface a specific message.
- **Entitlements — correct, but portal-dependent.** `Apps/iOS/Ammo/Ammo.entitlements:5-12` and
  `Apps/iOS/AmmoWidgets/AmmoWidgets.entitlements` both declare
  `group.com.brandon.ammo` and `$(AppIdentifierPrefix)com.brandon.ammo.shared`. Both are genuinely
  used — App Group at `Apps/iOS/Shared/SharedStore.swift:8-21`, shared Keychain group at
  `Apps/iOS/Shared/KeychainStore.swift:75-82`, and the widget really does read tokens
  (`Apps/iOS/AmmoWidgets/Timelines.swift:28`, `:83`, `:135`), so neither is over-requested. Both
  capabilities must exist on the App ID in the developer portal for the distribution profile to sign;
  that is App Store Connect state I cannot verify here.
- **`ITSAppUsesNonExemptEncryption: false` — correct.** `Apps/iOS/Ammo/Info.plist:40-41`. The only
  cryptographic code in the app is `SHA256` for the PKCE challenge
  (`Sources/UsageKit/PKCE.swift:2`, `:20`) and `SystemRandomNumberGenerator` for the verifier
  (`PKCE.swift:28-33`). Hashing is not encryption, and everything else is standard HTTPS via
  `URLSession` (`Sources/UsageKit/HTTP.swift:15`), which is exempt. `grep` for `CryptoKit|CommonCrypto|
  SecKey|AES|Curve25519` across `Sources/` and `Apps/` returns exactly one hit, the PKCE import. The
  declaration is accurate — keep answering "No" to the export-compliance question.

---

### S2 — No `PrivacyInfo.xcprivacy` (not currently mandatory, but add it)

**Severity:** SHOULD-FIX
**Guideline:** 5.1.1 / Apple's required-reason API policy (surfaces as automated email ITMS-91053,
not as a human rejection).

**Which required-reason APIs the app actually uses — the honest answer: none, in the shipping
configuration.** I checked each category:

| Category | Used? | Evidence |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | **Only behind a simulator guard** | `Apps/iOS/Ammo/Models/AccountStore.swift:153` — `UserDefaults.standard.bool(forKey: "AmmoHistoryPreview")`, inside `#if targetEnvironment(simulator)` opened at `:148`. Excluded from a device/App Store build. |
| `…FileTimestamp` | No | No `creationDate`, `modificationDate`, `attributesOfItem`, `resourceValues`, `stat`/`fstat`/`getattrlist` anywhere in `Sources/` or `Apps/`. |
| `…DiskSpace` | No | No `volumeAvailableCapacity*`, `statfs`, `NSFileSystemFreeSize`. |
| `…SystemBootTime` | No | No `systemUptime`, `mach_absolute_time`. |
| `…ActiveKeyboards` | No | No `activeInputModes`. |

Persistence is plain file I/O into the App Group (`SharedStore.swift:168-175`,
`AccountDeletionStore.swift:47-51`) plus Keychain — none of which are required-reason APIs. There are
zero third-party SDKs (`Package.swift:11-15`), so no vendored manifest is inherited.

**Remediation.** Add the manifest anyway, to both targets, so the answer is on record and so a future
un-guarding of `AccountStore.swift:153` doesn't silently create a violation. Add
`Apps/iOS/Ammo/PrivacyInfo.xcprivacy` (and a copy in `Apps/iOS/AmmoWidgets/`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
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

If you ship the demo-mode flag from §B1 using `@AppStorage`/`UserDefaults` — which is the natural
implementation — you **must** then add:

```xml
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>CA92.1</string>
			</array>
		</dict>
	</array>
```

`CA92.1` = "access info from the app itself / app group the app is a member of" — which is exactly the
use here. Register both files in `Apps/iOS/project.yml` under each target's `sources` so `xcodegen`
copies them into the bundle root.

---

### S3 — 4.2 Minimum Functionality: comfortably clear, but know the argument

**Severity:** SHOULD-FIX (posture only — no change strictly required)
**Guideline:** 4.2 Design — Minimum Functionality; 4.2.2 (web clippings).

**Is it a web wrapper?** No, and this is easy to demonstrate:

- The only web view in the entire app is the OAuth sheet — `SFSafariViewController` for Claude
  (`Apps/iOS/Ammo/Onboarding/WebAuth.swift:8-16`) and `ASWebAuthenticationSession` for Codex/Cursor
  (`WebAuth.swift:53-64`, `:149-157`). There is no `WKWebView` anywhere in the codebase.
- Everything else is native SwiftUI rendering normalized models
  (`Sources/UsageKit/Models.swift`), not remote HTML.

**What defends 4.2, concretely:**

- Three distinct native surfaces: Usage (`Apps/iOS/Ammo/UI/ContentView.swift`), On-demand
  (`Apps/iOS/Ammo/UI/OnDemandView.swift`, 426 lines of multi-scope monetary presentation), History
  (`Apps/iOS/Ammo/UI/HistoryView.swift`, 443 lines with a contribution heatmap at
  `Apps/iOS/Shared/ActivityHeatmap.swift`).
- Real data transformation, not passthrough: usage history is derived and reset-aware
  (`Sources/UsageKit/UsageHistory.swift`), refresh cadence is adaptive
  (`Sources/UsageKit/UsageRefreshSchedule.swift`, `Apps/iOS/Shared/RefreshLedger.swift`), and three
  incompatible provider payloads are normalized into one model
  (`ClaudeProvider.swift:203-249`, `CodexProvider.swift`, `CursorProvider.swift:192-265`). None of
  these providers offers this view on the web.
- **Widgets are the strongest 4.2 defense in the app, and they carry real weight.** Three widget
  kinds (`Apps/iOS/AmmoWidgets/AmmoWidgets.swift:5-11`) across six family/size combinations including
  a Lock Screen `accessoryCircular` gauge (`:45`), all user-configurable via `AppIntent`
  (`Apps/iOS/AmmoWidgets/AccountIntent.swift:46-52`), with the extension performing its own
  refreshes (`Timelines.swift:28`, `:83`, `:135`). System-integration features that a website
  categorically cannot provide are precisely what 4.2 asks for. This app has them, plus background
  refresh (§S1). I would not expect a 4.2 rejection on a build a reviewer can actually see.

The 4.2 risk is therefore *entirely downstream of §B1*: a reviewer who can only see "No accounts yet"
has seen an app with no functionality at all. Fix B1 and 4.2 takes care of itself.

**4.1 Copycat — clean.** Original name, original icon (§L1), no clone of a provider's own app.

---

### S4 — Accessibility and quality: good, with two gaps

**Severity:** SHOULD-FIX
**Guideline:** 4.0 Design / general quality (not usually a hard rejection, but it is what a reviewer
pokes at).

**Verified working:**

- **Dynamic Type** holds at Accessibility Large —
  `Screenshots/ammo-device-build13-dynamic-type-accessibility-large.png` shows no clipping, no
  truncation, bars and percentages intact. Text is sized with semantic fonts throughout
  (`Apps/iOS/Shared/UsageComponents.swift:49`, `:57`, `:61`) rather than fixed points.
- **Light and dark** both correct — `Screenshots/ammo-device-build13-light.png`,
  `…-build13-dark.png`. Colors are semantic (`.primary`, `.secondary`, `.quaternary`), and the
  bar's fill degrades to `.primary` in non-full-color widget rendering modes
  (`UsageComponents.swift:39-41`).
- **Error states are humane and non-technical.** `Sources/UsageKit/UsageFailure.swift:5-14` defines a
  closed set of eight categories; raw errors are logged privately and never displayed
  (`UsageRefreshCoordinator.swift:221` uses `privacy: .private`). Copy at
  `UsageComponents.swift:328-361`. Confirmed on device in
  `Screenshots/ammo-error-states-final-build13-dark.jpg` — "Update took too long" with a *Try Again*
  button, "Taking a short break" for rate limiting, and the cached data still visible beneath.
- **Endpoint returns garbage** → `UsageError.malformedResponse` (`ClaudeProvider.swift:42`,
  `CursorProvider.swift:34`) → classified `.invalidResponse` (`UsageFailure.swift:35`) → renders
  *"Update unavailable — Cursor returned something Ammo couldn't read"*
  (`UsageComponents.swift:335`, `:354`) with the last good snapshot preserved. Cursor additionally
  rejects a structurally-valid but empty payload (`CursorProvider.swift:38-41`). This is better than
  most apps do.
- **Empty states exist on every tab** — `ContentView.swift:177`, `OnDemandView.swift:17` and `:23`
  (including a distinct "no on-demand data" case with a Refresh action), `HistoryView.swift:41` and
  `:141`.
- **Widget empty/loading states** — `WidgetViews.swift:31-40`, plus VoiceOver labels for every gauge
  state including staleness and failure (`WidgetViews.swift:217-243`).
- 66 offline decode/behaviour tests pass (`swift test`), covering all three provider parsers, the
  refresh schedule, history derivation, and lock-screen presentation.

**Gap 1 — token expiry has no in-app recovery.** See §L3. This is the one real quality defect.

**Gap 2 — no `.privacySensitive()` on any widget.** `grep -rn "privacySensitive" Apps` → 0 hits. The
Lock Screen `accessoryCircular` gauge (`AmmoWidgets.swift:45`, `WidgetViews.swift:191-202`) renders a
percentage and the provider logo on a locked device. This is **not** a guideline violation — usage
percentages are not sensitive by Apple's definition, and `Screenshots/…-widget-privacy-safe.png`
shows the Home Screen case is fine. But if you later add account labels or dollar balances to a Lock
Screen family, `.privacySensitive()` becomes necessary. Worth adding now on any monetary value.

---

## NOTE findings

### N1 — 3.1.1 external purchase links: already handled correctly

`Apps/iOS/Ammo/UI/OnDemandView.swift:43` and `:86` open external URLs, one of which
(`https://chatgpt.com/admin/billing`, `Apps/iOS/Ammo/Models/CodexWorkspaceBillingPolicy.swift:20`) is
a page where a user can add paid credit to a digital service. That is squarely 3.1.1 territory
outside the US storefront. The code already gates it: `CodexWorkspaceBillingPolicy.availability`
(`:26-35`) resolves the live storefront via `Storefront.current`
(`OnDemandView.swift:78-82`) and permits the billing link **only** when the country code is `USA`,
failing closed on `nil` or unresolved (`:29-34`), with the button suppressed entirely at
`OnDemandView.swift:96-102`. The comment at `CodexWorkspaceBillingPolicy.swift:23-25` shows this was
deliberate. This is correct and better than most apps manage. Two follow-ups: (a) confirm the
*"View usage"* link (`:21`, `chatgpt.com/codex/settings/usage`) is genuinely informational and lands
on a page with no purchase call-to-action, since it is **not** storefront-gated; (b) mention the gate
in the Review Notes so a reviewer testing on a non-US account understands why the button is absent.

### N2 — 5.1.1(v) Account Sign-In / Deletion: defensible, prepare the answer

Ammo creates no account of its own; it authenticates to accounts the user already has. The
account-deletion requirement therefore does not apply. If challenged, the answer is that Ammo *does*
provide complete local deletion — `AccountStore.remove(_:)`
(`Apps/iOS/Ammo/Models/AccountStore.swift:65-82`) marks a tombstone, deletes the Keychain item, the
refresh ledger, the shared state, and the usage history, and every persistence store independently
re-checks the tombstone before writing (`Apps/iOS/Shared/AccountDeletionStore.swift:29-40`,
`SharedStore.swift:89`, `:119`, `KeychainStore.swift:18`). Ammo cannot delete a user's Anthropic /
OpenAI / Cursor account, and should not claim to; direct users to the provider. The related clause —
*"let people use your app without a login where possible"* — is answered by §B1's demo mode.

### N3 — 4.8 Login Services: unlikely to be raised, answer ready

4.8 requires an equivalent privacy-preserving login option when a third-party or social login is used
to **set up or authenticate the user's primary account** in your app. Ammo has no primary account:
the sign-ins at `WebAuth.swift:32`, `:114` and `ClaudeOnboardingView.swift:74` authorize read access
to the user's *own* existing service, and none of the three providers is a social login service in
4.8's sense. Sign in with Apple is not applicable. If asked, say exactly that.

### N4 — Icon and name: "Ammo" + a bullet motif, 4+ rating

`Apps/iOS/Ammo/AppIcon.icon/Assets/Vector 3.png` is a stylized bullet form inside an abstract "A"
(`Vector.png`). It is geometric and non-realistic, and the app has no weapons content. A 4+ rating is
correct and I would not expect 1.1.1 to be raised. Flagging only so it is not a surprise: if it ever
is, the answer is that "ammo" is used metaphorically for remaining allowance, which the app's own
copy already establishes (`ContentView.swift:181` — *"see how much ammo you have left"*).

### N5 — 5.6 Developer Code of Conduct: manage the public-repo language

Open-sourcing is your strongest 5.2.2 evidence and you should do it. But the repo as written hands a
provider's legal team a ready-made complaint, and a provider complaint to Apple is the most likely
route to a 5.6 / 5.2.2 removal *after* approval:

- `SPEC.md:10`, `SPEC.md:343` — "reverse-engineered".
- `SPEC.md:160-161` — "These are undocumented APIs and may drift."
- `Sources/UsageKit/CursorProvider.swift:6-7` — "private dashboard summary".
- `Apps/iOS/Assets/Official/cursor-app-icon.png`, `codex-app-icon.png` — competitors' app icons as
  checked-in build inputs (§L1).
- No `LICENSE` file.

Before you link the repo in Review Notes: rewrite those three phrases as described in §L4, remove the
`Assets/Official/` directory per §L1, and add a license. The technical content stays; the
provocations go.

### N6 — SPEC.md contradicts the shipping architecture

`SPEC.md:41-43` states the widget extension *"reads cached UsageSnapshots via App Group; never touches
the network or tokens directly."* It does both:
`Apps/iOS/AmmoWidgets/Timelines.swift:28`, `:83`, `:135` call
`UsageRefreshCoordinator.shared.refresh(...)`, which loads Keychain tokens at
`Apps/iOS/Shared/UsageRefreshCoordinator.swift:101` and performs network requests. The code comment at
`Apps/iOS/AmmoWidgets/AccountIntent.swift:5-8` is the accurate one. Not a rejection risk on its own —
but if you cite the repo as evidence for "here is exactly what the app does", the document you cite
should be right about what the app does.

---

## Predicted 5.2.2 fight — how it surfaces, and the response

### When and how it arrives

The provider-credential question will **not** be the first rejection. The first rejection is 2.1
(§B1), because the reviewer cannot get past the empty state to see anything worth objecting to. Once
demo mode ships and a human sees the app working, there are three realistic triggers, in descending
likelihood:

1. **The Content Rights declaration.** You answer "Yes, my app accesses third-party content" in App
   Store Connect. This routes the submission to a reviewer who is primed to ask for rights evidence.
2. **The logos** (§L1) — the most visible, most concrete thing to object to. Expect 5.2.5 first, since
   it is easier to write than 5.2.2.
3. **The description**, if it names Anthropic/OpenAI/Cursor without a disclaimer, or the Review Notes,
   if they describe the auth mechanism in more detail than necessary.

Expected wording of the 5.2.2 variant:

> Guideline 5.2.2 - Legal - Intellectual Property - Third-Party Sites/Services
> Your app accesses or provides access to a third-party service. Specifically, your app retrieves
> account and usage information from Anthropic, OpenAI, and Cursor. Please provide documentary
> evidence, such as a signed authorization from the third party, confirming that you have the
> necessary rights to access this service, or remove the functionality.

The 5.2.5 variant is quoted in §L1.

### The factual response

Keep it short, factual, and about *what the code does*. Do not argue policy, do not compare yourself to
competitors in the response (that argument works on a forum, not with App Review), and do not
volunteer detail about client identifiers unless asked directly.

> Ammo does not access a third-party service on its own behalf. It is a client that displays a user's
> own account data, retrieved with that user's own credentials, on that user's own device.
>
> 1. **The user authenticates directly with the provider.** Ammo never sees or handles a password. The
>    user signs in inside the provider's own web page, presented in `ASWebAuthenticationSession` /
>    `SFSafariViewController`, using standard OAuth 2.0 with PKCE (RFC 7636). Ammo receives only the
>    resulting authorization code.
> 2. **There is no server.** Ammo has no backend of any kind. Every network request goes directly from
>    the user's device to the provider's own host. No data is proxied, relayed, logged, aggregated, or
>    seen by the developer. This is independently verifiable in the open-source repository — the app
>    contains exactly six outbound hosts, all of them the providers' own.
> 3. **Nothing is collected.** Ammo's App Privacy declaration is "Data Not Collected", and that is
>    literally true: there is no analytics SDK, no crash reporter, no advertising identifier, and no
>    third-party dependency of any kind. Credentials are stored only in the iOS Keychain, marked
>    `ThisDeviceOnly`, and are deleted when the user removes the account or the app.
> 4. **No third-party content is republished.** Ammo displays numbers describing the signed-in user's
>    own remaining allowance — percentages, reset times, and balances. It does not display, cache, or
>    redistribute any provider content, model output, or another user's data.
> 5. **Provider names and logos are used referentially**, solely to identify which of the user's own
>    accounts each row belongs to. Ammo's name, icon, and design are original. The app states in its
>    description and in-app that it is independent and not affiliated with, endorsed by, or sponsored
>    by these companies.
>
> The app is fully open source at <REPO URL>, so every claim above can be verified in the source
> rather than taken on trust.

### The evidence that actually helps, ranked

1. **The public repository URL**, with a `README` section titled "What Ammo does not do" listing: no
   server, no telemetry, no data collection, no credential transmission. This is the single most
   persuasive artifact you have, and it costs nothing.
2. **"Data Not Collected"** on the privacy label. A reviewer weighing a rights question treats a clean
   privacy label very differently from a data-collecting one.
3. **Zero dependencies** (`Package.swift:11-15`) — trivially checkable, and it forecloses the "what is
   your SDK doing" line of questioning.
4. **Demo mode** (§B1) — it lets the reviewer see that the app is a viewer, not a service.
5. **A working support URL** where the app's independence is stated in writing.

### If they insist on "documentary evidence"

There is no signed authorization to produce, and saying so plainly is better than stalling. The
response is: Ammo does not access a third-party *service* on its own account — it accesses the
reviewer-user's *own* account, at that user's explicit direction, using credentials that user supplied
through the provider's own sign-in page, on that user's device. This is the same relationship as an
email client, a password manager, or a bank aggregator. Ask them to identify what specific content
they believe requires authorization. If it is the logos, offer to remove or replace them immediately
(§L1 gives you a same-day path) — resolve the 5.2.5 half instantly, and the 5.2.2 half usually goes
with it. Only escalate to the App Review Board if a second reviewer repeats the demand without
identifying specific content.

---

## App Review Notes — draft

Paste directly into App Review Notes. Replace the two bracketed placeholders.

```
WHAT AMMO DOES
Ammo shows developers how much of their AI coding-tool allowance is left. It reads
usage/quota information from three services the user already pays for — Claude
(Anthropic), Codex (OpenAI), and Cursor — and displays it in the app and in Home
Screen and Lock Screen widgets. Ammo is free, has no in-app purchases, and sells
nothing.

REVIEWING WITHOUT AN ACCOUNT — PLEASE START HERE
No account is needed to review this app. On first launch, tap "See a demo" on the
"No accounts yet" screen. This loads clearly-labelled sample data and exercises
every feature:
  • Usage tab — three sample accounts with limit windows and reset countdowns
  • On-demand tab — sample personal, team, and shared spending pools
  • History tab — 12 weeks of sample daily-activity history
  • Widgets — add any Ammo widget from the Home Screen gallery; the sample
    accounts appear in the widget's account picker
Demo mode is clearly marked as sample data, makes no network requests, and can be
exited from the Usage toolbar at any time.

We cannot supply a demo account for the three providers themselves: these are
third-party services, we cannot create accounts on Apple's behalf, and sharing our
own credentials would expose paid usage tied to a real person. Demo mode exists
specifically so the app is fully reviewable without one.

ARCHITECTURE — NO SERVER, NO DATA COLLECTION
Ammo has no backend. Every network request goes directly from the user's device to
the provider's own servers. Nothing is proxied, logged, aggregated, or transmitted
to us. There is no analytics SDK, no crash reporter, no advertising identifier, and
no third-party dependency of any kind.

Sign-in uses standard OAuth 2.0 with PKCE (RFC 7636), presented in
ASWebAuthenticationSession / SFSafariViewController so the user authenticates on the
provider's own page. Ammo never sees a password. Tokens are stored only in the iOS
Keychain with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, and are deleted when
the user removes the account or deletes the app.

Ammo is fully open source: [REPO URL]. Every claim above can be verified in the
source.

INDEPENDENCE
Ammo is an independent app and is not affiliated with, endorsed by, or sponsored by
Anthropic, OpenAI, or Anysphere. Provider names and logos appear only to identify
which of the user's own accounts a row belongs to. Ammo's name, icon, and design are
original. Ammo displays only the signed-in user's own allowance figures; it does not
display, store, or redistribute any provider content.

TECHNICAL NOTES
• Background App Refresh (BGAppRefreshTask, id com.brandon.ammo.refresh) keeps the
  widgets current. Cadence adapts to remaining allowance and known reset times.
• During Codex sign-in only, Ammo runs a listener on 127.0.0.1:1455 to receive the
  OAuth redirect, because that provider's flow redirects to localhost.
  ASWebAuthenticationSession cannot intercept an http://localhost redirect itself.
  The listener is restricted to the loopback interface, rejects non-loopback peers,
  accepts only a callback matching the PKCE state value it generated, and is shut
  down as soon as sign-in finishes or is cancelled.
• The On-demand tab contains a link to a provider billing page. It is shown only on
  the United States storefront, where an external purchase call-to-action does not
  require an entitlement, and is hidden on all other storefronts. Reviewing on a
  non-US account will correctly show no such button.
• iPhone only, portrait only, iOS 18.0+.

Contact: [SUPPORT EMAIL] — happy to answer any question before rejecting; we can
turn around a build same-day.
```

---

## What I could not verify from the repo

These depend on App Store Connect state, the developer portal, or a real archive/device run:

1. **Whether the app icon survives archiving** (§L2). The `.xcodeproj` is gitignored, so the shipped
   asset-catalog output cannot be inspected from source. Run the `xcodebuild archive` check in §L2.
2. **Whether the App ID `com.brandon.ammo` has App Groups and Keychain Sharing enabled** on the
   developer portal, and whether `group.com.brandon.ammo` and the
   `com.brandon.ammo.shared` Keychain group exist and are attached to the distribution profile. If
   not, the archive will fail to sign, or the widget will silently fail to read tokens on the App
   Store build (`Apps/iOS/Shared/KeychainStore.swift:40-43` degrades to `nil` with only a log line).
3. **Whether any App Store Connect metadata exists at all** — the repo has none, but you may have
   entered some directly in the web UI.
4. **Live provider behaviour.** All 66 passing tests are offline fixture decodes. `SPEC.md:158-159`
   states Cursor's contract has *"live verification pending"*; `CursorProvider.swift:7` asks for the
   contract to be kept date-stamped. If any endpoint has drifted since 2026-07-21, a reviewer with an
   account would see the `.invalidResponse` state rather than data. Re-verify all three providers
   against live accounts immediately before submitting.
5. **Whether `Storefront.current` resolves during review** (`OnDemandView.swift:78`). On a TestFlight
   or review device without a resolvable storefront it returns `nil`, which correctly fails closed
   (`CodexWorkspaceBillingPolicy.swift:33`) — but I could not observe the actual value.
6. **Whether port 1455 is free on the review device** (§S1). No fallback exists.
7. **Real-device widget rendering in Tinted and Clear Home Screen modes.** The code handles
   `widgetRenderingMode` (`ProviderLogo.swift:13`, `:64-69`; `UsageComponents.swift:39-41`) and
   `Screenshots/` shows full-colour only. Verify tinted rendering on a device before submitting —
   `PRODUCT.md:35` commits to it.
8. **VoiceOver end-to-end.** Labels are present in code (`WidgetViews.swift:187`, `:202`, `:217-243`;
   `ContentView.swift:130`, `:229`) but I could not run the screen reader.
9. **Whether the repository is actually public yet, and under what license.** There is no `LICENSE`
   file today. Both must be true before the Review Notes cite the repo as evidence.
