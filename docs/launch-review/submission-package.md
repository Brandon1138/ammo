# Ammo — App Store Connect submission package

**Scope.** Everything Brandon pastes into App Store Connect for the first
submission, in one document. Drafted against the tree at branch
`claude/mik-167-submission-metadata` (bundle ID `com.brandon.ammo`, marketing
version `0.1.0`, iPhone-only, portrait-only, iOS 18.0+). The tree carries
`CURRENT_PROJECT_VERSION: 17` (`Apps/iOS/project.yml:19`); that is the current
source value, **not** a submission decision. The build number that is actually
uploaded is chosen against live App Store Connect state at §5 gate 7 and
step 11, so nothing in this document assumes build 17 is available or final.

**Authorities.** `docs/launch-remediation-operator-checklist.md` §"App Store
Connect" (trademark and App Privacy rules), `docs/launch-review/app-review.md`
§B2/§B3/§B4/§L1 and the Review Notes draft, `docs/privacy-policy.md`, `PRODUCT.md`.

**Source of truth for build facts.** `Apps/iOS/project.yml:18-19` (version/build),
`Apps/iOS/project.yml:22` and `:58` (`TARGETED_DEVICE_FAMILY: "1"`, iPhone only),
`Sources/UsageKit/Models.swift:14` (`ProviderID.supported` = Claude, Codex,
Cursor, OpenRouter), `Apps/iOS/AmmoWidgets/AmmoWidgets.swift:5-11` (three widgets).

**Drift flagged during drafting.** Read §6 before pasting anything — the
`app-review.md` Review Notes draft predates OpenRouter and says "three
services"/"three sample accounts". This document says four. Screenshots on disk
are build-13 captures and are not from any release candidate.

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
Included limits, reset times, and on-demand balances for the AI coding accounts you already use — on your Home Screen.
```

118 characters (App Store Connect counts the em dash as one character). "You
already use", not "you already pay for" — see the accuracy note under the
description.

### Description (4000 char limit)

```
Ammo shows how much of your AI coding allowance is left, without opening four dashboards.

Connect the accounts you already use, and Ammo puts every included limit, reset countdown, and on-demand balance on one screen — and on your Home Screen.

USAGE
See each account's included windows as plain meters: session and weekly windows, monthly model allowances, and the time until each one resets. Personal, team, and organization scopes stay separate instead of being averaged into one number.

ON-DEMAND
Included allowance and paid continuation capacity are different things, so Ammo keeps them apart. The On-demand tab shows the balances, spending limits, and pools your provider reports for your account.

HISTORY
Ammo records the usage it observes on your device and charts it per account and per limit, so you can see how a week actually went rather than guessing from the current number.

WIDGETS
Three widget families, all configurable per account:
• Account — one account, small or medium.
• Accounts — up to four accounts in your chosen order: small, medium, and large, plus a taller portrait size on iOS 27 and later.
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

2,598 characters. Deliberately absent: the word "unlimited", any pricing claim
about a provider, any claim Ammo grants or extends allowance, any unshipped
feature (Antigravity is `deferred` at
`Apps/iOS/Ammo/Onboarding/ProviderSignInSheet.swift:19` and is therefore not
mentioned anywhere in this package).

**Two accuracy constraints this copy is written around (2.3 — Accurate
Metadata):**

- **Do not say the accounts are paid.** Not all four providers require a paid
  account: OpenRouter reports a free tier, and Ammo presents it —
  `Sources/UsageKit/OpenRouterKeyPresentation.swift:100-109` renders
  "Free models: 50 req/day" for a free-tier key, and the demo fixture itself
  marks OpenRouter free tier (`Apps/iOS/Shared/DemoModeStore.swift:90`). Both
  the promotional text and the description therefore say "the accounts you
  already use". "Paid continuation capacity" in the ON-DEMAND paragraph is
  about the on-demand pools themselves, not a claim about every provider.
- **Do not promise widget sizes the reviewer's OS cannot show.** The tall
  portrait family is appended only under `if #available(iOS 27.0, *)`
  (`Apps/iOS/Shared/WidgetAccountPresentation.swift:94-100`), and the
  landscape `systemExtraLarge` family is deliberately never declared because
  Ammo ships `TARGETED_DEVICE_FAMILY = 1`. On iOS 18–26 the Accounts widget
  offers small, medium, and large only. "Accounts" also has exactly four
  ordered slots (`SelectAccountsIntent`, `Apps/iOS/AmmoWidgets/AccountIntent.swift:77-99`),
  hence "up to four accounts".

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
| Version | `0.1.0` (must match `MARKETING_VERSION`, `Apps/iOS/project.yml:18`) |
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
   **Retention wording, everywhere:** removing an account inside Ammo deletes
   its Keychain item and local records (`KeychainStore.delete`, reached from
   `Apps/iOS/Ammo/Models/AccountStore.swift` account removal). Deleting the app
   is *not* a deletion guarantee — iOS has no uninstall callback, so
   `SecItemDelete` never runs on uninstall and iOS alone controls whether the
   items persist. This is exactly what `docs/privacy-policy.md:25-28` says, and
   no surface in this package may promise more than that.
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
   `NSPrivacyCollectedDataTypes` — consistent with the answers above. Their
   `NSPrivacyAccessedAPITypes` arrays are still empty on this branch and must
   gain the App Group `UserDefaults` reason `1C8F.1` before submission; that is
   a required-reason declaration, not a data-collection declaration, so it does
   not change any answer in this section. See §6.3.

The App Privacy answers, the privacy manifests, `docs/privacy-policy.md`, and
the Review Notes in §3 must all keep saying the same thing — including the
qualified uninstall/retention wording in point 2. If one changes, all four
change.

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

**The App Review Notes field caps at 4,000 characters.** The block below
measures 3,870 characters with `[SUPPORT EMAIL]` (15 characters) still in
place. A realistic ~30-character support address lands the pasted total near
3,885 — under the cap, but with limited slack: if the address is longer than
about 145 characters, drop one Technical Notes bullet. Re-count after pasting;
App Store Connect counts what it receives.

```
WHAT AMMO DOES
Ammo shows developers how much of their AI coding-tool allowance is left,
reading usage/quota data from four services the user already has accounts
with — Claude (Anthropic), Codex (OpenAI), Cursor (Anysphere), OpenRouter — in
the app and in Home Screen widgets. Free, no in-app purchases.

REVIEWING WITHOUT AN ACCOUNT — PLEASE START HERE
No account is needed.
1. Launch Ammo. The Usage tab shows a "No accounts yet" empty state.
2. Tap "See a demo".
3. Four labelled sample accounts load — "Codex sample", "Claude sample",
   "Cursor sample", "OpenRouter sample" — each marked "Sample data":
   • Usage — sample limit windows with reset countdowns.
   • On-demand — sample personal allocations and an API-key spending pool.
   • History — 12 weeks (84 days) of sample history; tap a row to open it.
   • Widgets — see below.
4. Exit via "Exit Demo" in the Usage toolbar; demo data never overwrites real
   accounts.
Demo mode makes no network requests: a marker file plus generated fixtures, no
credentials.

WIDGETS
With demo mode on, long-press the Home Screen, tap "+", search "Ammo", and add
any of the three; each is configured from the sample accounts:
• "Account" — one sample account: small or medium.
• "Accounts" — four ordered slots: small, medium, large, plus a taller
  portrait size only on iOS 27 and later.
• "Activity" — one account/limit pair. The picker lists only samples that have
  a usage window, so the OpenRouter sample does not appear there.

WHY WE CANNOT SUPPLY PROVIDER DEMO CREDENTIALS
These accounts are not ours to hand over. Each one belongs to an individual
account holder at a third-party service, and a shared credential carries that
holder's full account privileges — spending, billing, and any team or
workspace access — along with their private usage. Demo mode exists so the
whole app is reviewable without sharing anyone's credential.

ARCHITECTURE — NO SERVER, NO DATA COLLECTION
Ammo has no backend. Every request goes directly from the device to the
provider's own servers; nothing is proxied, logged, or sent to us. No
analytics SDK, no crash reporter, no advertising identifier, no third-party
dependency. Notifications are local only; no push entitlement.

Sign-in uses each provider's own web page in ASWebAuthenticationSession /
SFSafariViewController — Ammo never sees a password. OpenRouter instead takes
an API key the user creates in their own dashboard. Tokens/keys live only in
the iOS Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Remove
Account deletes the local Keychain item and related data; iOS controls
whether Keychain items persist after uninstall. Verifiable:
https://github.com/Brandon1138/ammo

INDEPENDENCE
Ammo is independent, not affiliated with, endorsed by, or sponsored by
Anthropic, OpenAI, Anysphere, or OpenRouter. Provider names/logos only
identify which of the user's own accounts a row belongs to, and Ammo's name,
icon, and design are original.

TECHNICAL NOTES
• Background App Refresh (BGAppRefreshTask, id com.brandon.ammo.refresh)
  keeps widgets current; cadence adapts to allowance left and reset times.
• During Codex sign-in only, Ammo runs a listener on 127.0.0.1:1455 for the
  OAuth redirect, because Codex redirects to localhost, which
  ASWebAuthenticationSession cannot intercept. It is bound to loopback,
  rejects non-loopback peers, accepts only its own PKCE callback, and shuts
  down when sign-in ends.
• Settings has an "Export Raw Usage Payloads" debug action: recent provider
  response bodies via the system share sheet. Auth headers/token responses
  are never included.
• The On-demand tab can link to the provider's own billing page, only on the
  United States storefront, where an external purchase call-to-action needs
  no entitlement; fails closed elsewhere.
• iPhone only, portrait only, iOS 18.0+.

Contact: [SUPPORT EMAIL]
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
`Apps/iOS/project.yml:49` (`ITSAppUsesNonExemptEncryption: false`). Because the
key is present and false, App Store Connect should not ask at all on upload —
if it does ask, the answers above are the ones that match the binary.

**Verified caveat:** the key is set on the **app** target only. The widget
extension's `Apps/iOS/AmmoWidgets/Info.plist` has no
`ITSAppUsesNonExemptEncryption` key (`project.yml:73-79` does not add it). Export
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

**Before answering Yes, read the recorded provenance — it is now mixed, not
uniform.** The §L1 remediation has been carried out in part.
`Apps/iOS/Shared/SOURCES.md` is the per-file evidence index and
`docs/asset-resourcing.md` holds the clause quotations, verified URLs, and
per-provider verdicts (all retrieved 2026-08-26). Current state:

- **Cursor** (`logo-cursor`, `logo-cursor-menu`, `logo-cursor-monochrome`) —
  re-sourced from Anysphere's own published brand archive at `cursor.com/brand`,
  downloaded unauthenticated, installed unmodified and undistorted. The
  extraction from Cursor's shipped app icon is gone from the binary.
  Permitted-with-conditions; the one stated condition ("Refer to us as Cursor.
  Not Cursor AI or Cursor Code.") is met.
- **OpenRouter** (`logo-openrouter`) — replaced byte-for-byte with the official
  glyph from `openrouter.ai/brand`, whose page states "Every configuration of
  the OpenRouter mark, ready to use" and describes the Glyph variant as being
  for "avatars, favicons, small sizes". Permitted-with-conditions.
- **Claude** (`logo-claude`) and **Codex / OpenAI** (`logo-codex`,
  `logo-codex-menu`, `logo-openai-monochrome`) — **not-established.** Anthropic
  grants logo use only "as specifically permitted by us and only in materials we
  approve beforehand," supplies the image itself, and publishes no self-serve
  kit; OpenAI gates its logo downloads behind a `brand.openai.com` login and
  publishes no Codex mark at all. Neither could be re-sourced. Those files are
  left in place with the verdict recorded rather than guessed at, and
  `docs/asset-resourcing.md` carries the operator recommendation: request
  written permission (partnercomms@openai.com / marketing@anthropic.com), or
  swap those three imagesets for a neutral in-house monochrome monogram and keep
  the plain-text provider names.

The *names* remain referential in every case, and both vendors' terms support
that independently: Anthropic's Claude Code page permits accurately saying "in
plain text" what your product works with, and OpenAI's guidelines restrict model
names in app titles — which Ammo does not use. **The remaining exposure is the
Claude and Codex glyph artwork, and that is operator judgment, recorded at §5
gates 1–2.**

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
https://brandon1138.github.io/ammo/privacy-policy/
```

Operator checklist §2: this URL is published by GitHub Pages from `site/` on the
public repo (`.github/workflows/pages.yml`, source `site/privacy-policy/index.html`),
and it goes live automatically on the next push to `main`. Still **open it in a
logged-out browser before entering it**. Do not use a repository blob URL unless
the repo is public, and do not use a URL that redirects through a login. The
published page must match `docs/privacy-policy.md` as shipped, which in turn must
match the §2 answers; the effective date in that file is August 14, 2026.

---

## 5. Operator entry checklist

Brandon's remaining App Store Connect work, in order. Everything above is
paste-ready; everything below is an action only he can take.

**Gates — do these before touching App Store Connect**

1. **Partly done — evidence recorded, two verdicts outstanding.** Clause-level
   brand/trademark evidence for all four providers is captured in
   `docs/asset-resourcing.md` (verified URLs, verbatim clauses, retrieved
   2026-08-26) and indexed per asset file in `Apps/iOS/Shared/SOURCES.md`. Note
   `https://www.anthropic.com/brand` 404s — the real page is
   `https://www.anthropic.com/legal/trademark-guidelines`. Verdicts: Cursor and
   OpenRouter permitted-with-conditions; Claude and OpenAI/Codex logos
   **not-established**. Remaining operator judgment: either obtain written
   permission from Anthropic (marketing@anthropic.com) and OpenAI
   (partnercomms@openai.com), or exclude those glyphs per gate 2. This gate also
   still covers provider **service/API** authorization, which is a separate
   question from mark use and is not settled by the above.
2. **Partly done.** The Cursor and OpenRouter glyphs have been re-sourced from
   the vendors' own published brand assets and the source URL, clause, and
   retrieval date are recorded in `Apps/iOS/Shared/SOURCES.md`. The Claude and
   Codex/OpenAI glyphs could not be re-sourced — no vendor kit is publicly
   available for either. Before answering Content Rights, decide those three
   imagesets: ship them on written permission, or replace them with the neutral
   monochrome monogram described in `docs/asset-resourcing.md` (a per-asset
   change in `ProviderLogo.swift`, not a UI redesign). Do not answer Content
   Rights until that decision is recorded.
3. Decide EU Digital Services Act trader/non-trader status in App Store Connect
   and complete verification if required. If unresolved, exclude EU storefronts
   rather than guessing.
4. Privacy policy publishing is automated: merging this change deploys `site/` to
   GitHub Pages, putting `docs/privacy-policy.md` live at
   `https://brandon1138.github.io/ammo/privacy-policy/`. The only remaining step
   is to open that URL in a logged-out browser after the merge and confirm it
   loads and matches `docs/privacy-policy.md`.
5. Confirm GitHub Issues are enabled and
   `https://github.com/Brandon1138/ammo/issues` loads logged out.
6. Fill `[SUPPORT EMAIL]` in the §3 Review Notes.
7. Query App Store Connect for the app record and all used build numbers before
   choosing the release build. Do not assume build 17 remains available.
8. Run archive, entitlement, privacy-report, device, live-contract, widget, and
   accessibility passes on the exact release-candidate commit. Reuse no older proof.
9. Capture fresh native App Store screenshots from that exact candidate. Existing
   build-13 captures and any pre-remediation build-17 captures are not final.
   Check that no credential, personal label, or unrelated device bezel appears.

**App Store Connect entry, in order**

10. Query for the app record for `com.brandon.ammo`; create it only if it is
    still absent. Set app name `Ammo`, primary language, and bundle ID.
11. Query the highest used build number, choose a strictly higher candidate,
    update `CURRENT_PROJECT_VERSION`, regenerate XcodeGen, and rebuild/archive.
12. Categories: Developer Tools (primary), Utilities (secondary). Price: Free.
13. Paste §1 into the version localization and re-check character counts.
14. Enter the verified Support URL and Privacy Policy URL from §4.
15. Upload screenshots captured from the exact processed candidate.
16. App Privacy: answer **No** to data collection (§2), then confirm the listing
    preview reads **Data Not Collected**. Do not declare User ID.
17. Complete the DSA declaration/storefront decision from gate 3.
18. Age rating: answer per §4 and confirm **4+**.
19. Content Rights: answer only after gates 1–2 are resolved.
20. Upload the exact archive, wait for processing, and resolve every validation
    warning, including any `ITMS-91053` required-reason warning.
21. Attach the processed build and confirm its displayed marketing version,
    build number, commit provenance, and screenshots all match the candidate.
22. Export compliance: if prompted, answer per §4.
23. Paste §3 into App Review Notes. Leave "Sign-in required" off; Ammo has no
    first-party account. Do not leave Review Notes blank.
24. Install the processed build through internal TestFlight and repeat the
    non-destructive smoke test before public App Review submission.
25. Set manual release for the first submission, then submit only after every
    gate above has recorded evidence.
26. Watch for the first reviewer message. If authorization or mark provenance is
    requested, provide the saved evidence or remove the affected provider/asset;
    do not substitute argument for evidence.

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
3. **Required-reason `UserDefaults` declaration: expected `1C8F.1`, not yet on
   this branch.** Production notification preferences resolve
   `UserDefaults(suiteName: AppGroup.id)` —
   `Sources/UsageKit/Notifications/NotificationPreferencesStorage.swift:14-17`,
   constructed with `AppGroup.id` (`group.com.brandon.ammo`,
   `Apps/iOS/Shared/SharedStore.swift:9`) at
   `Apps/iOS/Ammo/Models/NotificationSettingsModel.swift:20-22` and
   `Apps/iOS/Ammo/Services/UsageNotificationService.swift:14-16`. That is
   access to a container shared by the app and its extension inside the same
   App Group, so the expected reason is **`1C8F.1`** — not `CA92.1`. The only
   `UserDefaults.standard` read in app code
   (`Apps/iOS/Ammo/Models/AccountStore.swift:396`) sits inside
   `#if targetEnvironment(simulator)` (`:390`), so it is absent from device
   binaries and cannot be used to argue `CA92.1`. Note the
   `UserDefaults(suiteName:) ?? .standard` fallback on
   `NotificationPreferencesStorage.swift:16`: it only triggers if the App Group
   is unavailable, which on a correctly provisioned build it is not.

   **Current state on this branch:** both manifests still carry
   `<key>NSPrivacyAccessedAPITypes</key><array/>`
   (`Apps/iOS/Ammo/PrivacyInfo.xcprivacy:11-12`,
   `Apps/iOS/AmmoWidgets/PrivacyInfo.xcprivacy:11-12`), so an upload from this
   branch should be expected to draw `ITMS-91053`. PR #36
   (`codex/appstore-technical-blockers`) adds exactly the
   `NSPrivacyAccessedAPICategoryUserDefaults` / `1C8F.1` dictionary to **both**
   manifests and is **open, not merged** as of 2026-08-25 — verified against
   the PR diff, not assumed. **Gate:** merge that remediation, then confirm
   `1C8F.1` in both manifests *and* in the privacy report generated from the
   exact archive being submitted (§5 gate 8, step 20). This does not change the
   §2 App Privacy answers: a required-reason declaration is not a
   data-collection declaration.
4. **`ITSAppUsesNonExemptEncryption` is app-target only.** Present and `false`
   at `Apps/iOS/Ammo/Info.plist:40-41`; absent from
   `Apps/iOS/AmmoWidgets/Info.plist`. Correct as-is (see §4), recorded so it is
   not mistaken for a defect.
5. **Screenshots on disk are build 13, not the final release candidate.** `Screenshots/` contains
   `ammo-device-final-build13-*.png` and friends; `project.yml:19` sets
   `CURRENT_PROJECT_VERSION: 17`. The operator checklist §8 requires captures
   from the exact submitted build, so `app-review.md` §B4's suggestion to reuse
   the existing captures is stale. New captures required (§5 gate 9).
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
