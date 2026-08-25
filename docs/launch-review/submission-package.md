# Ammo — App Store Connect submission package

**Scope.** Everything Brandon pastes into App Store Connect for the first
submission, in one document. Drafted against the tree at branch
`claude/mik-167-submission-metadata` (bundle ID `com.brandon.ammo`, marketing
version `0.1.0`, build `17`, iPhone-only, portrait-only, iOS 18.0+).

**Authorities.** `docs/launch-remediation-operator-checklist.md` §"App Store
Connect" (trademark and App Privacy rules), `docs/launch-review/app-review.md`
§B2/§B3/§B4/§L1 and the Review Notes draft, `docs/privacy-policy.md`, `PRODUCT.md`.

**Source of truth for build facts.** `Apps/iOS/project.yml:16-17` (version/build),
`Apps/iOS/project.yml:20` and `:52` (`TARGETED_DEVICE_FAMILY: "1"`, iPhone only),
`Sources/UsageKit/Models.swift:14` (`ProviderID.supported` = Claude, Codex,
Cursor, OpenRouter), `Apps/iOS/AmmoWidgets/AmmoWidgets.swift:5-11` (three widgets).

**Drift flagged during drafting.** Read §6 before pasting anything — the
`app-review.md` Review Notes draft predates OpenRouter and says "three
services"/"three sample accounts". This document says four. Screenshots on disk
are build 13, not build 17.

---

## 1. Store metadata

Hard rules applied to every field below (operator checklist §6, `app-review.md`
§B4): **no provider trademark — OpenAI, ChatGPT, Codex, Claude, Anthropic,
Cursor, Anysphere, Grok, OpenRouter, Gemini, Antigravity — appears in the app
name, subtitle, or keywords.** Referential use in the description body is fine
and is paired with an explicit independence paragraph.

### App Name (30 char limit)

```
Ammo
```

4 characters. No provider mark, no descriptor tail. `Ammo for Claude`,
`Claude Usage`, `Codex Meter` would all invite 2.3.7 / 5.2.5.

### Subtitle (30 char limit)

```
AI coding usage, at a glance
```

28 characters. App Review treats the subtitle as name-adjacent, so it stays
generic.

### Promotional text (170 char limit)

Editable without a new build — keep it to current-build facts only, never
"coming soon" or version teasers (2.3.1).

```
Included limits, reset times, and on-demand balances for the AI coding accounts you already pay for — on your Home Screen and Lock Screen.
```

138 characters (App Store Connect counts the em dash as one character).

### Description (4000 char limit)

```
Ammo shows how much of your AI coding allowance is left, without opening four dashboards.

Connect the accounts you already pay for, and Ammo puts every included limit, reset countdown, and on-demand balance on one screen — and on your Home Screen and Lock Screen.

USAGE
See each account's included windows as plain meters: session and weekly windows, monthly model allowances, and the time until each one resets. Personal, team, and organization scopes stay separate instead of being averaged into one number.

ON-DEMAND
Included allowance and paid continuation capacity are different things, so Ammo keeps them apart. The On-demand tab shows the balances, spending limits, and pools your provider reports for your account.

HISTORY
Ammo records the usage it observes on your device and charts it per account and per limit, so you can see how a week actually went rather than guessing from the current number.

WIDGETS
Three widget families, all configurable per account:
• Account — one account, small or medium, plus a Lock Screen circular gauge.
• Accounts — your configured accounts in your chosen order, small through the tall Home Screen size.
• Activity — daily usage activity for one account and limit.
Background App Refresh keeps them current, and the cadence adapts to how much allowance is left and when it resets.

RESET ALERTS
Optional local notifications when a window renews, so you know you have room again without opening the app.

YOUR CREDENTIALS STAY ON YOUR DEVICE
Ammo has no server. Every request goes straight from your iPhone to the provider you chose. Sign-in uses each provider's own web sign-in page — Ammo never sees a password. Tokens are stored only in the iOS Keychain, device-local and non-syncing, and are deleted when you remove the account. There is no analytics SDK, no crash reporter, no advertising identifier, and no third-party dependency of any kind. Ammo is free, has no in-app purchases, and sells nothing.

TRY IT WITHOUT AN ACCOUNT
Tap "See a demo" on first launch to load clearly labelled offline sample data across every tab and widget.

INDEPENDENCE
Ammo is an independent app. It is not affiliated with, endorsed by, or sponsored by Anthropic, OpenAI, Anysphere, or OpenRouter. Claude, Codex, ChatGPT, Cursor, and OpenRouter are trademarks of their respective owners. Ammo requires you to sign in to your own existing account with each service; it does not provide, grant, resell, or extend any allowance, and it displays only the figures your own account already reports.

Ammo is open source: https://github.com/Brandon1138/ammo

REQUIREMENTS
iPhone, iOS 18.0 or later.
```

2,624 characters. Deliberately absent: the word "unlimited", any pricing claim
about a provider, any claim Ammo grants or extends allowance, any unshipped
feature (Antigravity is `deferred` at
`Apps/iOS/Ammo/Onboarding/ProviderSignInSheet.swift:19` and is therefore not
mentioned anywhere in this package).

### Keywords (100 char limit)

```
usage,quota,limits,tokens,developer,coding,widget,rate limit,allowance,meter
```

76 characters. No spaces after commas — a space costs a keyword character. No
provider marks: `claude`, `anthropic`, `openai`, `chatgpt`, `codex`, `cursor`,
`anysphere`, `openrouter` are all standard 5.2.5 rejections here and buy nothing
the description does not already carry.

### Other listing fields

| Field | Value |
|---|---|
| Primary category | Developer Tools |
| Secondary category | Utilities |
| Price | Free, no in-app purchases |
| Copyright | `2026 Brandon Aron` |
| Version | `0.1.0` (must match `MARKETING_VERSION`, `Apps/iOS/project.yml:16`) |
| "What's New" | First release. Omit for a first submission if App Store Connect does not require it. |

---

## 2. App Privacy answer sheet

### The answers

| Question | Answer |
|---|---|
| Do you or your third-party partners collect data from this app? | **No** |
| Result shown on the listing | **Data Not Collected** |
| Follow-up data-type questions | None — App Store Connect stops asking after "No" |
| Privacy Policy URL | Required. See §4. |

**Do not declare "Contact Info → User ID."** This is the one tempting wrong
answer. The OAuth account identifier (`Sources/UsageKit/Models.swift`,
`OAuthTokens.accountID`) never leaves the device
(`Apps/iOS/Shared/KeychainStore.swift:17-37`), so declaring it would be
*inaccurate in the other direction* and invites 5.1.1 questions that do not
otherwise exist (`app-review.md` §B3).

Also do not declare Identifiers, Diagnostics, Usage Data, or Purchases. None are
transmitted anywhere Brandon can reach.

### Rationale (keep this; it is the record if App Review asks)

Apple's definition of "collect" is transmitting data off-device in a way that
makes it accessible to the developer or its partners beyond servicing the
request. Ammo transmits only to the user's own provider, at the user's
direction, with the user's own credentials, and retains nothing off-device.

1. **No developer backend.** Every request goes through `URLSession` directly to
   the provider host (`Sources/UsageKit/HTTP.swift`); the only hosts in the
   binary are the four providers' own hosts plus the `chatgpt.com` billing and
   usage links in `Apps/iOS/Ammo/Models/CodexWorkspaceBillingPolicy.swift:20-21`,
   which are opened in the user's browser, not fetched.
2. **Credentials stay in the Keychain.** `Apps/iOS/Shared/KeychainStore.swift`
   uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — device-local,
   non-synchronizing, no iCloud Keychain, no device-to-device backup migration.
3. **Everything else is App Group local.** Account labels, usage snapshots,
   refresh scheduling, and history live in the App Group container
   (`Apps/iOS/Shared/SharedStore.swift`) so the widgets can render.
4. **No analytics, no crash reporting, no advertising identifier, no
   third-party SDK.** `Package.swift` declares zero external dependencies.
5. **Notifications are local only.** `UNUserNotificationCenter` local requests
   (`Apps/iOS/Ammo/Services/UsageNotificationService.swift:104`); there is no
   push entitlement and no `registerForRemoteNotifications` call.
6. **Demo mode is fully offline.** `Apps/iOS/Shared/DemoModeStore.swift` — a
   marker file plus generated fixtures, no credentials, no network.
7. **Privacy manifests ship in both bundles.**
   `Apps/iOS/Ammo/PrivacyInfo.xcprivacy` and
   `Apps/iOS/AmmoWidgets/PrivacyInfo.xcprivacy` both declare
   `NSPrivacyTracking = false`, empty `NSPrivacyTrackingDomains`, empty
   `NSPrivacyCollectedDataTypes` — consistent with the answers above.

The App Privacy answers, the privacy manifests, `docs/privacy-policy.md`, and
the Review Notes in §3 must all keep saying the same thing. If one changes, all
four change.

### Re-check trigger list

Re-open this questionnaire — and this document — before shipping any build that
adds any of the following. Each one can flip "Data Not Collected" to a
declaration, and shipping a stale answer is a 5.1.1 problem, not a paperwork one:

- Any analytics or product-metrics SDK, first- or third-party.
- Any crash or error reporting service (Crashlytics, Sentry, MetricKit uploads).
- Any developer-operated backend, proxy, relay, or cache — including a "just for
  rate limiting" proxy in front of a provider API.
- Any remote/push notification support (adds a push token, an identifier).
- Any remote config, feature flag, or A/B testing service.
- Any account system, sync, iCloud/CloudKit storage, or cross-device handoff of
  account data.
- Any advertising, attribution, or install-referrer integration.
- Any third-party SDK at all — `Package.swift` gaining a remote dependency is
  the tripwire; check what it links and what it phones home.
- Any support/feedback form that submits to a service Brandon controls.
- Any change that sends usage snapshots, logs, or diagnostics anywhere other
  than the user's own provider.
- Any new required-reason API usage — that changes `PrivacyInfo.xcprivacy`, not
  the questionnaire, but the review is the same review (see §6).

---

## 3. App Review Notes

Paste as-is after replacing the one bracketed placeholder. This supersedes the
draft at the end of `app-review.md`, which predates OpenRouter.

**The App Review Notes field caps at 4,000 characters.** The block below is
3,956 with `[SUPPORT EMAIL]` still in place, so the substituted address must be
about 40 characters or shorter — or trim a Technical Notes bullet to make room.
Re-count after pasting; App Store Connect counts what it receives.

```
WHAT AMMO DOES
Ammo shows developers how much of their AI coding-tool allowance is left, reading
usage/quota data from four services the user already has accounts with — Claude
(Anthropic), Codex (OpenAI), Cursor (Anysphere), OpenRouter — and shows it in the
app and in Home Screen and Lock Screen widgets. Free, no in-app purchases.

REVIEWING WITHOUT AN ACCOUNT — PLEASE START HERE
No account is needed.
1. Launch Ammo. The Usage tab shows a "No accounts yet" empty state.
2. Tap "See a demo".
3. Four labelled sample accounts load — "Codex sample", "Claude sample", "Cursor
   sample", "OpenRouter sample" — each marked "Sample data":
   • Usage — sample limit windows with reset countdowns.
   • On-demand — sample personal allocations and an API-key spending pool.
   • History — 12 weeks (84 days) of sample history; tap a Usage row to open it.
   • Widgets — see below.
4. Exit via "Exit Demo" in the Usage toolbar, top right; demo data never
   overwrites real accounts.
Demo mode makes no network requests: a marker file plus generated fixtures, no
credentials.

WIDGETS
With demo mode on, long-press the Home Screen, tap "+", search "Ammo", and add any
of the three. All are per-account configurable via "Edit Widget"; the four sample
accounts appear in the picker.
• "Account" — small, medium, and Lock Screen circular (for that one, long-press
  the Lock Screen, tap Customize, add it below the clock).
• "Accounts" — all configured accounts, small through tall.
• "Activity" — daily usage activity for one account and limit.

WHY WE CANNOT SUPPLY PROVIDER DEMO CREDENTIALS
The accounts belong to third parties, not to us: we cannot create them on Apple's
behalf, all four are paid, and sharing ours would expose a real person's paid
usage and billing surface. Demo mode exists so the app is fully reviewable
without one.

ARCHITECTURE — NO SERVER, NO DATA COLLECTION
Ammo has no backend. Every request goes directly from the device to the provider's
own servers; nothing is proxied, logged, or sent to us. No analytics SDK, no crash
reporter, no advertising identifier, no third-party dependency. Notifications are
local only; there is no push entitlement.

Sign-in uses each provider's own web page in ASWebAuthenticationSession /
SFSafariViewController — Ammo never sees a password. OpenRouter instead takes an
API key the user creates in their own OpenRouter dashboard. Tokens and keys live
only in the iOS Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly) and
are deleted with the account or the app. All verifiable:
https://github.com/Brandon1138/ammo

INDEPENDENCE
Ammo is independent and is not affiliated with, endorsed by, or sponsored by
Anthropic, OpenAI, Anysphere, or OpenRouter. Provider names and logos appear only
to identify which of the user's own accounts a row belongs to. Ammo's name, icon,
and design are original, and it shows only the user's own figures.

TECHNICAL NOTES
• Background App Refresh (BGAppRefreshTask, id com.brandon.ammo.refresh) keeps
  widgets current; cadence adapts to allowance left and reset times.
• During Codex sign-in only, Ammo runs a listener on 127.0.0.1:1455 for the OAuth
  redirect, because that provider redirects to localhost and
  ASWebAuthenticationSession cannot intercept an http://localhost redirect. It is
  bound to loopback, rejects non-loopback peers, accepts only a callback matching
  its own PKCE state, and shuts down when sign-in ends.
• Settings has an "Export Raw Usage Payloads" debug action: recent provider
  response bodies, shared via the system share sheet. Authentication headers and
  token responses are never included.
• The On-demand tab can link to the provider's own billing page, only on the
  United States storefront, where an external purchase call-to-action needs no
  entitlement. It fails closed elsewhere.
• iPhone only, portrait only, iOS 18.0+.

Contact: [SUPPORT EMAIL] — happy to answer anything before rejecting; we can ship
same-day.
```

**Placeholder to fill:** `[SUPPORT EMAIL]` — one address Brandon actually reads.
The repo URL is already filled in and matches the Support URL in §4. This text is
deliberately denser than the `app-review.md` draft, which is ~5,400 characters
and would not fit the field.

---

## 4. Compliance answers and URL slots

### Export compliance

| App Store Connect question | Answer |
|---|---|
| Does your app use encryption? | **Yes** — HTTPS is encryption. |
| Does it qualify for any of the exemptions? | **Yes** — it only uses standard iOS/HTTPS encryption and implements none of its own. |
| Result | Exempt; no CCATS, no annual self-classification report. |

**This must agree with the Info.plist key, and it does.**
`ITSAppUsesNonExemptEncryption` is set to `<false/>` at
`Apps/iOS/Ammo/Info.plist:40-41`, generated from
`Apps/iOS/project.yml:47` (`ITSAppUsesNonExemptEncryption: false`). Because the
key is present and false, App Store Connect should not ask at all on upload —
if it does ask, the answers above are the ones that match the binary.

**Verified caveat:** the key is set on the **app** target only. The widget
extension's `Apps/iOS/AmmoWidgets/Info.plist` has no
`ITSAppUsesNonExemptEncryption` key (`project.yml:70-78` does not add it). Export
compliance is evaluated per uploaded app record, not per embedded extension, so
this is correct as-is and needs no change; it is recorded here so nobody
"discovers" it mid-submission and assumes something is broken.

Nothing in the tree implements custom cryptography: no CryptoKit key exchange, no
bundled crypto library, `Package.swift` has zero external dependencies. PKCE
(RFC 7636) uses SHA-256 hashing for the challenge, which is not an encryption
algorithm for export purposes and does not defeat the exemption.

### Age rating

Target **4+**. Nothing in the app triggers a higher tier (`app-review.md` §B3
adjacent answers, §N4 on the abstract "Ammo"/bullet motif).

| Questionnaire item | Answer |
|---|---|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Prolonged Realistic Violence | None |
| Sexual Content or Nudity | None |
| Profanity or Crude Humor | None |
| Alcohol, Tobacco, or Drug Use or References | None |
| Mature/Suggestive Themes | None |
| Horror/Fear Themes | None |
| Medical/Treatment Information | None |
| Simulated Gambling / Gambling | None |
| Contests | None |
| Unrestricted Web Access | **No** — sign-in web views are confined to the provider's own authorization pages, and the only other outbound links are two fixed provider URLs opened in the system browser. There is no in-app browser with an address bar. |
| User-Generated Content | **No** |
| Age Assurance / age verification features | **No** |
| Made for Kids | **No** |

The questionnaire is revised periodically; answer whatever the current form
shows, but any answer that pushes the rating above 4+ means something in the
build changed and this document is stale.

### Content Rights

| Question | Answer |
|---|---|
| Does your app contain, show, or access third-party content? | **Yes** |

**Basis for answering yes, and for the rights assertion.** Ammo displays two
kinds of third-party material:

1. **Provider names** ("Claude", "Codex", "Cursor", "OpenRouter") as labels
   identifying which of the user's own accounts a row belongs to.
2. **Provider logos** (`Apps/iOS/Shared/ProviderAssets.xcassets/`, rendered via
   `Apps/iOS/Shared/ProviderLogo.swift`) in the add-account menu, in section
   headers, and in widgets.

Both are nominative/referential use: the mark identifies the trademark owner's
own service, only as much of the mark as needed is used, and nothing on any
surface suggests sponsorship or endorsement. The app name, icon, and design are
original, and the independence disclaimer appears in the description, the
privacy policy, and the Review Notes.

**Before answering Yes, confirm the logo provenance is defensible**
(operator checklist §5, `app-review.md` §L1). §L1 records that the shipped
glyphs were pixel-extracted from the providers' shipping app icons via
`Apps/iOS/Scripts/extract-provider-glyphs.py`, with
`Apps/iOS/Assets/Official/*-app-icon.png` checked in as build inputs. That is a
weaker story than "used per their published brand guidelines". §L1's remediation
— re-source each asset from the vendor's own published brand kit and record the
source URL and permitted-use clause in a `SOURCES.md` next to the asset catalog —
converts "extracted from their icon" into a sentence that survives a legal
question. **This is a code/asset change and is out of scope for this document;
it is listed as a gate in §5.**

The third-party *data* shown (the user's own usage figures) is fetched with the
user's own credentials at the user's direction, and is the user's own account
data — it is not redistributed provider content.

### Support URL

```
https://github.com/Brandon1138/ammo/issues
```

Operator checklist §3: confirm Issues are **enabled** on the public repo and the
URL loads while logged out before entering it. A GitHub Issues URL is stronger
here than a bare `mailto:` because it doubles as the open-source evidence the
Review Notes rely on (`app-review.md` §B4). A 404, a repo root with Issues
disabled, or a bare mailto are all rejections. If Issues are disabled and cannot
be enabled, publish a support page next to the privacy policy instead — do not
leave the field pointing at something that does not accept contact.

### Privacy Policy URL

```
[PRIVACY POLICY URL]
```

Operator checklist §2: publish `docs/privacy-policy.md` at a stable HTTPS URL —
GitHub Pages off the public repo is fine — and **open it in a logged-out browser
before entering it**. Do not use a repository blob URL unless the repo is
public, and do not use a URL that redirects through a login. The published page
must match `docs/privacy-policy.md` as shipped, which in turn must match the §2
answers; the effective date in that file is August 14, 2026.

---

## 5. Operator entry checklist

Brandon's remaining App Store Connect work, in order. Everything above is
paste-ready; everything below is an action only he can take.

**Gates — do these before touching App Store Connect**

1. Decide the §4 Content Rights logo question. Either complete `app-review.md`
   §L1 remediation 1 (re-source each provider glyph from the vendor's published
   brand kit, record source URL and permitted-use clause), or consciously accept
   the current provenance. Do not answer Content Rights until this is settled.
2. Publish `docs/privacy-policy.md` at a stable HTTPS URL. Open it logged out.
3. Confirm GitHub Issues are enabled and
   `https://github.com/Brandon1138/ammo/issues` loads logged out.
4. Fill `[SUPPORT EMAIL]` in the §3 Review Notes.
5. Run the operator checklist's archive, entitlement, device, live-contract,
   widget, and accessibility passes on the exact commit being submitted. Do not
   reuse older evidence.
6. Capture fresh iPhone screenshots from **build 17**. The captures in
   `Screenshots/` are build 13 and cannot be used (operator checklist §8).
   Check no credential, personal label, or unrelated device bezel appears.

**App Store Connect entry, in order**

7. Create or select the app record for `com.brandon.ammo`. Set the app name
   `Ammo`, primary language, and bundle ID.
8. Categories: Developer Tools (primary), Utilities (secondary). Price: Free.
9. Paste §1 into the version's localization: subtitle, promotional text,
   description, keywords. Re-check character counts after paste — App Store
   Connect counts what it receives, not what this document claims.
10. Enter the Support URL and the Privacy Policy URL from §4.
11. Upload the build-17 screenshots for the current required iPhone sizes.
12. App Privacy: answer **No** to data collection (§2). Confirm the listing
    preview reads **Data Not Collected**. Do not declare User ID.
13. Age rating questionnaire: answer per §4; confirm the result is **4+**.
14. Content Rights: **Yes**, per the §4 basis and gate 1.
15. Upload the archive (App Store method), wait for processing, and resolve
    **every** validation warning before submitting — including any
    `ITMS-91053` required-reason-API warning (§6).
16. Attach the processed build to the version. Confirm the version string reads
    `0.1.0` and the build reads `17`.
17. Export compliance: if prompted, answer per §4 (uses encryption: yes;
    exempt: yes). If the Info.plist key is honored, no prompt appears.
18. Paste §3 into App Review Notes. Leave "Sign-in required" **off** — there is
    no app account. Do not leave Review Notes blank.
19. Set release option (manual release recommended for a first submission) and
    submit.
20. Watch for the reviewer's first message. If a 5.2.5 query arrives, respond
    with §4's Content Rights basis and `app-review.md`'s escalation guidance —
    offer to remove or replace the logos same-day rather than arguing.

---

## 6. Where the tree contradicted the docs

Recorded during drafting. None of these were fixed here — this document is
review/drafting only.

1. **`app-review.md`'s Review Notes draft is out of date on provider count.** It
   says "three services" and "three sample accounts" (Claude, Codex, Cursor).
   The shipping build supports four — `Sources/UsageKit/Models.swift:14` lists
   `.claude, .codex, .cursor, .openRouter`, and
   `Apps/iOS/Shared/DemoModeStore.swift:25-30` seeds four demo accounts
   including "OpenRouter sample". §3 above is corrected; the `app-review.md`
   draft should not be pasted.
2. **`app-review.md` §B3 says `PrivacyInfo.xcprivacy` does not exist.** It now
   exists in both bundles — `Apps/iOS/Ammo/PrivacyInfo.xcprivacy` and
   `Apps/iOS/AmmoWidgets/PrivacyInfo.xcprivacy` — and both declare no tracking
   and no collected data types. That finding is resolved.
3. **Required-reason API declaration is likely missing.** Both privacy manifests
   have an empty `NSPrivacyAccessedAPITypes`, but the app reads and writes
   `UserDefaults` (`Sources/UsageKit/Notifications/NotificationPreferencesStorage.swift:7-16`,
   `Apps/iOS/Ammo/Models/AccountStore.swift:396`,
   `Apps/iOS/Ammo/UI/SettingsView.swift:11`), including a suite shared with the
   widget extension. `NSPrivacyAccessedAPICategoryUserDefaults` is a
   required-reason API. Expect an `ITMS-91053` warning email on upload. This
   does **not** change the §2 App Privacy answers — a declared reason is not a
   data collection declaration — but it is a code change someone must make
   before or right after the first upload. Out of scope here; flagged as
   step 15 in §5.
4. **`ITSAppUsesNonExemptEncryption` is app-target only.** Present and `false`
   at `Apps/iOS/Ammo/Info.plist:40-41`; absent from
   `Apps/iOS/AmmoWidgets/Info.plist`. Correct as-is (see §4), recorded so it is
   not mistaken for a defect.
5. **Screenshots on disk are build 13, not build 17.** `Screenshots/` contains
   `ammo-device-final-build13-*.png` and friends; `project.yml:17` sets
   `CURRENT_PROJECT_VERSION: 17`. The operator checklist §8 requires captures
   from the exact submitted build, so `app-review.md` §B4's suggestion to reuse
   the existing captures is stale. New captures required (§5 gate 6).
6. **There is still no in-app "not affiliated" disclaimer.**
   `grep -ri "not affiliated" Apps/iOS Sources` returns zero hits, and
   `Apps/iOS/Ammo/UI/SettingsView.swift` (which now exists — Notifications,
   Display, Debug sections) has no About row and no privacy-policy link.
   `app-review.md` §L1 remediation 3 recommends one line in Settings or in the
   empty state; it is cheap and it is what Apple points at when deciding whether
   an app implies endorsement. Not required to submit — the disclaimer is in the
   description, the privacy policy, and the Review Notes — but it is the
   highest-value small change left.
7. **`PRODUCT.md` and `README.md` prose is not listing-safe.** Both predate the
   metadata rules and are written for a developer audience; §1's copy is written
   fresh rather than adapted from them, per `app-review.md` §B5.
