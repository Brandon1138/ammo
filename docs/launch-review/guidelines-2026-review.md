# Ammo — 2026 App Store Review Guidelines Second Pass

**Audit date:** 2026-08-25  
**Build reviewed:** `com.brandon.ammo` 0.1.0 (17), iPhone-only, iOS 18+  
**Tree reviewed:** `codex/mik-168-guidelines-sol` at `51b9b9b`  
**Scope:** review only; no product or submission changes

> **Research limitation:** live web retrieval was unavailable in this worker environment on
> 2026-08-25. In-app Browser returned `No browser is available`; direct retrieval of
> `developer.apple.com` failed with `Could not resolve host`. This report therefore cites official
> Apple URLs and identifies them with an attempted retrieval date of 2026-08-25, but it does not
> claim that their live wording was independently retrieved this turn. Guideline analysis uses the
> 2026-08-01 reviews, current repository evidence, and Apple requirements known as of 2026-08-25.
> Screenshot dimensions and other App Store Connect UI details can change without a numbered
> guideline update; re-check linked Apple pages from a networked environment immediately before
> submission.

## Executive verdict

| Area | Verdict | Short reason |
|---|---|---|
| 4.2 minimum functionality | **PASS** | Native history, normalization, notifications, and widgets make this materially more than a thin meter or web wrapper. |
| 5.2.2 third-party services and trademarks | **BLOCKER** | No evidence that provider terms specifically permit this access; three adapters use non-public surfaces and bundled marks lack adequate provenance. |
| 2.1 completeness and reviewer access | **PASS** | Shipped, labeled, offline demo covers all four providers and core surfaces without reviewer credentials. |
| 2.3 accurate metadata | **BLOCKER** | No current metadata or Review Notes exist in this tree; existing captures predate build 17 and do not fit a current screenshot slot. |
| App Privacy and privacy manifests | **BLOCKER** | App Privacy answers remain unproved in App Store Connect, and both manifests omit required-reason `UserDefaults` access. |
| 5.1.1 data collection and login | **BLOCKER** | Local data design is strong, but policy is unpublished and absent in-app; mandatory disclosure path is incomplete. |
| EU DSA trader status | **BLOCKER for EU** | No App Store Connect trader/non-trader declaration or verification evidence exists. |
| Screenshot requirements | **BLOCKER** | No native 6.9-inch, build-17 App Store screenshots exist in this tree. |

**Submission posture: DO NOT SUBMIT this tree yet.** Demo mode closes the previous near-certain
reviewer-access rejection, but legal authorization, privacy declarations, metadata, screenshots,
and EU compliance are not assembled. Several are App Store Connect form or upload gates before human
review.

## Sources and method

### Official Apple sources

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — attempted
  retrieval 2026-08-25; live access unavailable.
- [Overview of publishing your app on the App Store](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/overview-of-publishing-your-app-on-the-app-store/) — attempted retrieval 2026-08-25; live access unavailable.
- [App privacy details on the App Store](https://developer.apple.com/app-store/app-privacy-details/) —
  attempted retrieval 2026-08-25; live access unavailable.
- [Describing data use in privacy manifests](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests) — attempted retrieval 2026-08-25; live access unavailable.
- [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) — attempted
  retrieval 2026-08-25; live access unavailable.
- [Manage European Union Digital Services Act trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/) — attempted retrieval 2026-08-25; live access unavailable.
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/) — attempted retrieval 2026-08-25; live access unavailable.

### Repository basis

- Prior reviews: `docs/launch-review/app-review.md` and `docs/launch-review/red-team.md`, both dated
  2026-08-01 and written against `557e726`.
- Current tree: app, widget, XcodeGen manifest, privacy manifests, provider clients, onboarding,
  demo mode, policy draft, license, screenshots, and tests at `51b9b9b`.
- Verdict meanings: **PASS** means tree evidence supports compliance; **RISK** means submission can
  proceed only with a defensible App Review position or external App Store Connect evidence;
  **BLOCKER** means submission cannot be completed or likely cannot survive review without action.
- Review was static. Tests/builds were not run because task permits modifying only this document;
  build tools would write derived artifacts. Current machine reports Xcode 27.0 and iPhoneOS SDK
  27.0, but no signed archive or App Store Connect upload was inspected.

### Current submission-requirement snapshot

- Apple's known 2026 upload floor is Xcode 26 or later with the iOS 26 SDK or later. Source:
  [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/), attempted
  retrieval 2026-08-25. Ammo's iOS 18 deployment target (`Apps/iOS/project.yml:7`) can remain lower;
  deployment target and upload SDK are separate. Local Xcode 27 satisfies the likely toolchain floor,
  but only a release archive/upload proves the submitted binary.
- App Privacy answers, a public privacy-policy URL, support contact, content-rights declaration,
  age-rating answers, screenshots, reviewer contact/instructions, export-compliance answers, and the
  build are submission-package data, not inferred from source code. This tree supplies only a draft
  policy and an operator checklist; it does not prove those fields exist in App Store Connect.
- EU distribution additionally requires a DSA trader-status declaration and, for traders, successful
  verification of contact details displayed on the EU storefront.

## Area reviews

### 1. Guideline 4.2 — Minimum Functionality

**Apple rule.** Guideline 4.2 rejects apps whose lasting utility is too limited, including thin web
wrappers, content aggregators, and apps without enough native value. Source: [App Review
Guidelines](https://developer.apple.com/app-store/review/guidelines/#minimum-functionality), §4.2,
attempted retrieval 2026-08-25.

**Covered on 2026-08-01.** `app-review.md` §S3 already gave the right answer: Ammo is not a web
wrapper, normalizes incompatible provider payloads, maintains reset-aware history, refreshes in the
background, and supplies Home Screen and Lock Screen widgets. It concluded that 4.2 risk was mainly
downstream of the then-empty reviewer experience.

**Changed or missed.** That empty experience is gone. Build 17 adds an always-compiled demo, a
fourth provider, notification controls, richer account ordering and reconnection, and more widget
presentation. `Apps/iOS/Ammo/UI/ContentView.swift:95-109` exposes three distinct native tabs.
`Apps/iOS/Shared/DemoModeStore.swift:24-123` builds four providers plus 84 days of history per
account. `Apps/iOS/Ammo/Models/NotificationSettingsModel.swift:18-90` drives native
local-notification preferences. `Apps/iOS/AmmoWidgets/AmmoWidgets.swift:4-68` defines three WidgetKit
kinds, including configurable Home Screen and Lock Screen families.
`Apps/iOS/Ammo/UI/HistoryView.swift:29-99` and `Apps/iOS/Ammo/UI/OnDemandView.swift:13-102` are real
native analysis surfaces, not links to provider dashboards.

**Ammo verdict: PASS.** A usage-meter app can satisfy 4.2 when it does substantial device-native
work; Ammo does. Keep screenshots and Review Notes focused on history, alerts, cross-provider
normalization, and widgets. Calling it only a “usage meter” undersells the evidence.

### 2. Guideline 5.2.2 — Third-Party Services and Trademarks

**Apple rule.** Guideline 5.2.2 says an app using, accessing, monetizing access to, or displaying
content from a third-party service must be specifically permitted under that service's terms, and
authorization must be produced on request. Trademark/copyright assets are principally §5.2.1
(General), not §5.2.5; §5.2.2 governs service access. Source: [App Review
Guidelines](https://developer.apple.com/app-store/review/guidelines/#legal), §§5.2.1-5.2.2,
attempted retrieval 2026-08-25.

**Covered on 2026-08-01.** `app-review.md` predicted the 5.2.2 request accurately and drafted a
technical response based on user-directed access, OAuth, no backend, and no republishing. It also
flagged provider-logo provenance. `red-team.md` separately identified automated-access terms risk,
`User-Agent: codex-cli`, Cursor's synthesized web-session cookie, and inability to quote current
provider terms. One correction: the prior logo finding cited §5.2.5; current third-party mark analysis
belongs under §5.2.1 alongside §5.2.2.

**Changed or missed.** MIT `LICENSE` and `NOTICE` now exist, and `NOTICE:1-7` carries independence
and trademark language. `docs/privacy-policy.md:5-7` repeats the non-affiliation statement. Those are
useful, but no equivalent text exists in shipping Swift code
(`Apps/iOS/Ammo/UI/SettingsView.swift:17-110` has no About/legal section). The high-risk
implementation remains:

- Claude calls non-public OAuth usage/profile endpoints and reuses the Claude Code public client ID
  (`Sources/UsageKit/ClaudeProvider.swift:5-19,27-35`).
- Codex calls `chatgpt.com/backend-api/wham/usage`, reuses the Codex CLI public client ID, and sends
  `User-Agent: codex-cli` (`Sources/UsageKit/CodexProvider.swift:5-19,27-35`).
- Cursor says no public individual-plan API exists, reads `cursor.com/api/usage-summary`, and turns
  the OAuth token into a `WorkosCursorSessionToken` cookie
  (`Sources/UsageKit/CursorProvider.swift:3-16,51-56,324-329`).
- OpenRouter is materially safer because it calls documented `GET /api/v1/key` with an ordinary key
  and rejects management/provisioning keys (`Sources/UsageKit/OpenRouterProvider.swift:3-24,115-126`).
- Provider names and marks render throughout app and widgets
  (`Apps/iOS/Shared/ProviderLogo.swift:54-90`). Codex and
  Cursor glyphs are still extracted from tracked provider app icons
  (`Apps/iOS/Scripts/extract-provider-glyphs.py:2,11-13,120-128`;
  `Apps/iOS/Assets/Official/`). `NOTICE` attributes only
  OpenRouter's LobeHub asset; no per-asset license/source record proves the other marks' permitted use.

No current provider terms, brand rules, signed permission, or other documentary authorization exists
in this tree. Because live web was unavailable, this audit cannot determine whether any provider's
2026 terms now expressly allow or forbid Ammo's pattern. Code comments and public docs themselves
call Cursor's endpoint private/unofficial (`Sources/UsageKit/CursorProvider.swift:5-7`;
`CURSOR_RESEARCH.md:3-9`).

**Ammo verdict: BLOCKER.** This is an evidence blocker, not a finding that infringement is proven.
Before submission, establish clause-level permission for each shipping provider and mark, save the
evidence, and remove any provider that cannot be defended. Independently replace extracted assets
with licensed brand-kit files or neutral text/monograms, add an in-app independence notice, and stop
claiming `codex-cli` as Ammo's client identity. If App Review requests authorization today, tree has
nothing sufficient to upload.

### 3. Guideline 2.1 — App Completeness and Reviewer Access

**Apple rule.** Guideline 2.1 requires a final, fully testable build and the resources App Review
needs. For login-gated features, provide active demo credentials or a built-in demo mode that exposes
the functionality; explain non-obvious setup in Review Notes. Source: [App Review
Guidelines](https://developer.apple.com/app-store/review/guidelines/#app-completeness), §2.1,
attempted retrieval 2026-08-25.

**Covered on 2026-08-01.** `app-review.md` B1 correctly called the device build a blocker: demo data
was simulator-only, leaving reviewers at third-party login walls. It recommended an offline “See a
demo” route, visible sample labels, widget-compatible shared data, and clear Review Notes.

**Changed or missed.** Remediation landed. `Apps/iOS/Ammo/UI/ContentView.swift:197-209` exposes
**See a demo** on the
first empty screen. `Apps/iOS/Ammo/Models/AccountStore.swift:259-281` turns demo mode on/off, and
`:307-312` guarantees it makes no network refresh. Every account header says **Sample data**
(`Apps/iOS/Ammo/UI/ContentView.swift:319-325`). Fixtures cover all four shipping providers,
on-demand data, and 84 days of history (`Apps/iOS/Shared/DemoModeStore.swift:24-123`;
`Apps/iOS/AmmoTests/DemoModeTests.swift:6-20`). Demo state also reaches widget account queries
through `Apps/iOS/Shared/SharedStore.swift:139-143` and
`Apps/iOS/AmmoWidgets/AccountIntent.swift:40-65`. Real accounts remain untouched behind an App Group
marker (`Apps/iOS/Shared/DemoModeStore.swift:4-21`).

The missing Review Notes are a submission-metadata blocker under §2.3, but reviewer access in the
binary no longer depends on them: button is visible on first launch.

**Ammo verdict: PASS.** Use demo mode, not shared provider credentials. Review Notes should say:
launch, tap **See a demo**, inspect Usage/On-demand/History, then add widgets while demo remains on.
Do not claim runtime proof from `Apps/iOS/AmmoTests/DemoModeTests.swift`; this review did not run it.

### 4. Guideline 2.3 — Accurate Metadata

**Apple rule.** §§2.3.1-2.3.3 require all features to be apparent to App Review, metadata to describe
the submitted build accurately, and screenshots to show the app in use rather than unrelated title,
login, or splash art. App name/keywords must not misuse third-party marks. Source: [App Review
Guidelines](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata), §2.3,
attempted retrieval 2026-08-25.

**Covered on 2026-08-01.** `app-review.md` B4 found no submission metadata and supplied recommended
field posture: `Ammo` name, generic subtitle/keywords, provider names only in descriptive context,
an independence statement, public support/privacy URLs, and explicit Review Notes. It warned against
using old or unreviewable screenshots.

**Changed or missed.** Current tree still contains no Fastlane/App Store metadata or complete
submission package. `docs/launch-remediation-operator-checklist.md:6-24` is instructions, not final
copy. An unmerged `claude/mik-167-submission-metadata` branch is not evidence for this tree. Since the
old review, shipping scope grew from three to four providers, and notifications, reconnection,
account ordering, Codex Spark display, and new widget layouts landed. Any old draft must be reconciled
to build 17. The app also contains a release-visible **Export Raw Usage Payloads** debug surface
(`Apps/iOS/Ammo/UI/SettingsView.swift:74-84`) that Review Notes should identify so it is not mistaken for a hidden
diagnostic feature.

All 15 tracked `Screenshots/` files are old documentation captures: normal device files are
1080×2340, one cropped file is 971×1619, and debug JPGs are 368×800. Names identify build 13, while
submitted code is build 17 (`Apps/iOS/project.yml:18-19`). None matches the current 6.9-inch slot or shows
build-17 demo data.

**Ammo verdict: BLOCKER.** Submission cannot be assembled accurately from this tree. Draft and
review the complete App Store Connect field set, make provider prerequisites and independence clear,
name demo/debug paths in Review Notes, and use screenshots captured from the exact release build.

### 5. App Privacy Nutrition Labels and Privacy Manifests

**Apple rule.** App Store Connect requires developers to disclose app and third-party-partner data
collection for the App Privacy nutrition label and keep answers current. Privacy manifests are a
different artifact: bundled `PrivacyInfo.xcprivacy` files declare tracking, collected data, tracking
domains, and approved reasons for required-reason APIs. Uploads using a listed API without an
approved reason can be rejected by automated validation. Sources: [App privacy details on the App
Store](https://developer.apple.com/app-store/app-privacy-details/) and [Describing data use in
privacy manifests](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests),
attempted retrieval 2026-08-25.

**Covered on 2026-08-01.** Both reviews found no manifest and no App Privacy source of truth. They
recommended “Data Not Collected” because Ammo has no backend or integrated analytics/advertising
partner and its provider requests are user-directed. They also predicted an empty manifest because
the then-observed production code used no required-reason API.

**Changed or missed.** Both targets now contain byte-identical manifests
(`Apps/iOS/Ammo/PrivacyInfo.xcprivacy` and `Apps/iOS/AmmoWidgets/PrivacyInfo.xcprivacy`), each
declaring no tracking, no collected types, and no required-reason API (`:5-12`). A policy draft now
exists. “Data Not Collected” remains technically defensible: network requests go directly to the
chosen provider; tokens are stored in ThisDeviceOnly Keychain items
(`Apps/iOS/Shared/KeychainStore.swift:17-25`);
and `Package.swift:11-15` has no third-party package. User-initiated export through the share sheet
(`Apps/iOS/Ammo/UI/SettingsView.swift:74-84,102-104`) is not developer collection.

However, manifest is now under-declared. Production notification settings create an App Group
`UserDefaults` suite (`Apps/iOS/Ammo/Models/NotificationSettingsModel.swift:18-28`;
`Apps/iOS/Ammo/Services/UsageNotificationService.swift:13-21`), and
`Sources/UsageKit/Notifications/NotificationPreferencesStorage.swift:7-16,19-42` reads and writes it.
Apple's last-known reason
taxonomy distinguishes app-only defaults (`CA92.1`) from defaults shared in the same App Group
(`1C8F.1`). Ammo's production use matches **`1C8F.1`**, not `CA92.1`. The simulator-only
`UserDefaults.standard` preview at `Apps/iOS/Ammo/Models/AccountStore.swift:391-397` does not justify
a production reason. Because UsageKit is linked into both app and widget targets
(`Apps/iOS/project.yml:31-33,68-70`), inspect the
release binaries and generated privacy report; declaring `1C8F.1` in both manifests is the safe
expected result if both binaries contain the reference. Reconfirm exact reason wording on Apple's
live required-reason API page before changing it; live retrieval was unavailable here.

No tree artifact proves that App Store Connect contains the nutrition-label answers, that Apple has
accepted them, or that the draft policy URL was entered.

**Ammo verdict: BLOCKER.** Fix required-reason declarations, generate/archive the privacy report,
and record reviewed App Privacy answers in a submission package before entering them in App Store
Connect. “Data Not Collected” should remain the answer unless a backend, analytics/crash SDK,
partner-accessible telemetry, or other off-device developer/partner collection is added.

### 6. Guideline 5.1.1 — Data Collection, Login, and Account Controls

**Apple rule.** §5.1.1(i) requires a privacy-policy URL in App Store Connect and an easily accessible
policy link inside the app. Policy must identify collected data, collection, uses, retention/deletion,
and third parties receiving it. §5.1.1(v) requires apps without significant account-based features
to allow use without login where possible and requires in-app account deletion when the app supports
creating its own accounts. Source: [App Review
Guidelines](https://developer.apple.com/app-store/review/guidelines/#privacy), §5.1.1,
attempted retrieval 2026-08-25.

**Covered on 2026-08-01.** `app-review.md` B2/B3 and N2 correctly separated local linked-provider
accounts from an Ammo account: Ammo creates no primary account, so it cannot delete a user's
Anthropic/OpenAI/Cursor account. The review required a public policy, explained local deletion, and
recommended demo access. `red-team.md` traced tokens to Keychain and found no developer egress.

**Changed or missed.** Local privacy posture improved:

- Draft policy covers no backend, Keychain, App Group files, no telemetry SDK, demo mode, deletion,
  provider processing, and contact (`docs/privacy-policy.md:5-41`).
- Account removal is journaled and deletes Keychain, refresh state, cache, and history
  (`Apps/iOS/Shared/AccountMutationStore.swift:116-129`). Transient tombstone failures no longer
  authorize credential deletion (`Apps/iOS/Shared/AccountDeletionStore.swift:9-18`;
  `Apps/iOS/Shared/KeychainStore.swift:33-44`).
- Demo mode allows meaningful use without provider login
  (`Apps/iOS/Ammo/UI/ContentView.swift:197-209`).

Mandatory disclosure is still incomplete. Policy is a local Markdown draft with no stable public URL,
and `Apps/iOS/Ammo/UI/SettingsView.swift:17-110` contains no privacy-policy link. Its removal section also does not say
that deleting local credentials does **not** revoke the upstream provider session. More importantly,
onboarding understates credential privilege: `SPEC.md:20-24` admits Claude, Codex, and Cursor OAuth
tokens can do more than read usage, while user-facing Claude/Codex/Cursor screens describe approval
or usage access without that scope warning (`Apps/iOS/Ammo/Onboarding/ClaudeOnboardingView.swift:23-44`,
`Apps/iOS/Ammo/Onboarding/CodexOnboardingView.swift:39-65`,
`Apps/iOS/Ammo/Onboarding/CursorOnboardingView.swift:35-47`). OpenRouter clearly discloses
that an ordinary inference key is used and narrows behavior to `GET /api/v1/key`
(`Apps/iOS/Ammo/Onboarding/OpenRouterOnboardingView.swift:35-50`).

**Ammo verdict: BLOCKER.** Publish policy at stable HTTPS URL, enter it in App Store Connect, and link
it from Settings. Add concise in-app disclosures for provider processing, broader credential scope,
local-only deletion/non-revocation, and independence. Ammo-account deletion and Sign in with Apple
remain inapplicable because Ammo creates no account and provider authorization is for core external
account data, not login to an Ammo identity.

### 7. EU Digital Services Act Trader Status

**Apple requirement.** EU DSA marketplace rules require every developer distributing in the EU to
declare trader or non-trader status in App Store Connect. A trader must submit verifiable address,
phone number, and email; Apple displays verified contact information on EU product pages. A
non-trader product page states that EU consumer-protection rights applicable to contracts with
traders do not apply. Since 17 February 2025, apps without the required status cannot remain
available in the EU. Source: [Manage European Union Digital Services Act trader
requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/),
attempted retrieval 2026-08-25.

**Covered on 2026-08-01.** Neither review discussed DSA trader status. This was a material submission
omission.

**Changed or missed.** No `trader`, `Digital Services Act`, or DSA record exists in current tree.
That is expected because authoritative status lives in App Store Connect, but no operator evidence
was supplied. Public source, a free app, or individual enrollment does not automatically determine
status; classification turns on whether developer acts for purposes relating to trade, business,
craft, or profession. This review cannot make that legal choice from source code.

**Ammo verdict: BLOCKER for EU distribution.** Owner must decide status, enter it, complete any
verification, and capture App Store Connect proof. If unresolved, exclude EU storefronts rather than
marking non-trader by guess. Non-EU submission is not blocked by this specific item.

### 8. Current Screenshot Requirements

**Apple requirement.** App Store Connect accepts one to ten screenshots per device localization.
For a current iPhone-only submission, the primary 6.9-inch portrait target is **1320×2868 px**
(**2868×1320 px** landscape). A valid 6.9-inch set is used for smaller iPhone sizes, so a separate
6.5-inch set is not required when the current primary set is supplied. Screenshots must be JPEG or
PNG, show the app in use, and match the submitted build. Because `TARGETED_DEVICE_FAMILY` is iPhone
only (`Apps/iOS/project.yml:22,58,89`), no iPad screenshot set is required. Sources: [Screenshot
specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/)
and App Review Guideline §2.3.3, attempted retrieval 2026-08-25. Recheck the live size table before
upload because App Store Connect adds device classes independently of guideline revisions.

**Covered on 2026-08-01.** `app-review.md` B4 said “6.9 and 6.5 (or current required sets)” and
recommended existing build-13 device captures. That was appropriately tentative, but both sets are
not required under the known current simplified iPhone workflow, and existing files were never valid
submission assets at their native dimensions.

**Changed or missed.** No screenshot deliverable changed in this tree. Fifteen tracked images remain:
most are 1080×2340 physical-device documentation shots, debug images are 368×800, and one crop is
971×1619. None is 1320×2868; none is named for build 17 or demonstrates shipped demo mode. Upscaling
would meet pixel count while failing truth/quality review; capture natively on a 6.9-inch simulator
or matching device instead.

**Ammo verdict: BLOCKER.** Capture one to ten native build-17 screenshots at 1320×2868. Minimum useful
set: Usage with **Sample data**, On-demand, History, and Settings/notifications. Add widget imagery
only when it represents real current UI and does not substitute for in-app screenshots. Verify every
frame contains no real labels, credentials, stale build-13 behavior, or misleading device chrome.

## Ranked rejection risks

### 1. Third-party service authorization and mark provenance — BLOCKER

Most likely substantive human-review rejection. Content Rights answer, provider names, and logos make
third-party dependence obvious; source then shows non-public endpoints, first-party CLI client IDs,
`User-Agent: codex-cli`, Cursor cookie synthesis, and app-icon-derived glyphs. **Mitigation:** assemble
current clause-level ToS/brand evidence per provider, seek written permission where terms do not
specifically allow access, remove unsupported providers from shipping UI/metadata, replace marks with
licensed brand-kit assets or neutral identifiers, ship independence text, and prepare a short 5.2.2
response backed by documents rather than architecture claims alone.

### 2. Privacy package and required-reason manifest mismatch — BLOCKER

Most likely automated/upload or privacy-review failure. Both manifests say no required-reason APIs,
yet production uses App Group `UserDefaults`; policy exists only locally; no in-app link or App Store
Connect answer evidence exists. **Mitigation:** confirm and declare `1C8F.1` where release binaries
contain App Group defaults access, archive and inspect both bundled manifests/privacy report, publish
policy at stable HTTPS URL, link it in Settings, and review/transcribe “Data Not Collected” answers
against exact release code.

### 3. Incomplete and stale submission metadata — BLOCKER

Most likely pre-review submission stop or 2.3 rejection. Current tree lacks final description,
keywords, Review Notes, App Privacy answer sheet, DSA decision, and valid screenshots; tracked images
show build 13 at sizes that do not satisfy the required primary slot. **Mitigation:** create reviewed build-17 submission package,
declare provider prerequisites and independence, give exact demo instructions, complete DSA status,
capture native 1320×2868 demo screenshots, then validate every field against uploaded binary before
pressing Submit.

## Proposed Linear issues

### `legal(launch): establish 5.2.2 authorization for every shipping provider`

Record current terms clause and access basis for Claude, Codex, Cursor, and OpenRouter, including
OAuth client use and non-public usage endpoints. Obtain written authorization where terms do not
specifically permit Ammo. Produce App Review evidence packet; remove any provider that cannot be
defended before submission.

### `chore(assets): replace provider marks with licensed sources and ship attribution`

Replace Codex/Cursor app-icon-derived glyphs and any unproven Claude asset with brand-kit assets whose
source URL and permitted-use clause are recorded per file, or use neutral text/monograms. Delete
`Apps/iOS/Assets/Official` and extraction script from HEAD. Add Settings/About independence,
trademark, privacy-policy, support, and license links.

### `fix(codex): identify usage requests as Ammo instead of codex-cli`

Replace `User-Agent: codex-cli` with honest versioned Ammo identity derived from bundle metadata.
Audit other adapters for misleading first-party client headers and add transport assertions. If
endpoint rejects honest identity, treat that as provider-support evidence, not a reason to impersonate.

### `fix(privacy): declare App Group UserDefaults required reason in privacy manifests`

Production notification preferences use `UserDefaults(suiteName: AppGroup.id)`, while both manifests
declare empty `NSPrivacyAccessedAPITypes`. Confirm Apple's live taxonomy, add expected `1C8F.1` to
each release binary that contains the reference, generate Xcode privacy report, inspect both bundles,
and clear App Store Connect validation.

### `docs(privacy): publish policy and complete in-app disclosures`

Publish `docs/privacy-policy.md` at stable HTTPS URL, enter it in App Store Connect, and link it from
Settings. State provider processing, broader-than-usage credential capability, local retention,
local removal not revoking upstream sessions, support contact, and non-affiliation. Keep wording
aligned with actual Keychain/App Group code.

### `docs(launch): assemble build-17 App Store Connect submission package`

Draft final name, subtitle, promotional text, description, keywords, category, support/privacy URLs,
Content Rights answer, age rating, export compliance, App Privacy answers, and Review Notes. Avoid
provider marks in name/subtitle/keywords. Review Notes must direct reviewer to **See a demo**, describe
offline/sample behavior and widget setup, and identify raw-payload export.

### `chore(release): capture native 6.9-inch App Store screenshots from build 17`

Capture one to ten 1320×2868 PNG/JPEG screenshots from exact release build in demo mode. Include
Usage, On-demand, History, and Settings; show **Sample data** where applicable. Reject upscaled,
cropped, credential-bearing, personal-label, and build-13 assets.

### `chore(compliance): complete EU DSA trader-status declaration`

Owner decides trader/non-trader status, enters it in App Store Connect, completes required contact
verification, and records proof. If decision remains unresolved, exclude EU storefronts. Do not infer
non-trader status from free pricing or individual developer enrollment.

### `fix(account): confirm local removal and disclose upstream non-revocation`

Gate **Remove Account** with confirmation naming deleted local credentials/history and explaining that
provider session/account remains active upstream. Link provider session-management help where stable.
Update privacy policy and add regression coverage.

### `chore(release): validate signed archive and upload with current SDK`

Generate project from `Apps/iOS/project.yml`, archive Release with current accepted Xcode/iOS SDK,
verify iPhone-only device family, app icon, entitlements, both privacy manifests, Release-only content,
and successful App Store Connect processing. Record toolchain, archive SHA/build, validation output,
and resolution of every warning.
