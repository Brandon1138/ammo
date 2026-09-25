# App Store Connect progress, 2026-09-05

## Live app record

- Name: Ammo: AI Usage Tracker. Apple rejected the exact name Ammo as already used.
- Apple ID: 6808986067.
- Bundle ID and approved permanent SKU: com.brandon.ammo.
- Platform: iOS. Primary language: English (U.S.).
- Version: 0.1.0, Prepare for Submission.
- Listing: https://appstoreconnect.apple.com/apps/6808986067/distribution/ios/version/inflight

## Saved and verified

- Subtitle: AI coding usage, at a glance.
- Categories: Developer Tools, Utilities.
- Description, promotional text, keywords, support URL, and copyright entered using the submission package. Description clarifies OpenRouter API-key sign-in and does not advertise the iOS 27-only widget size. No em or en dashes in the saved description.
- Manual release selected; sign-in required disabled because the offline demo supports review.
- All four build-18 native 1320 x 2868 screenshots uploaded in order: Usage, On-demand, History, Settings. The 6.5-inch class inherits the 6.9-inch assets. Order and saved metadata independently rechecked in a fresh page.
- Age questionnaire completed: 4+ in 172 countries or regions, with regional equivalents shown by Apple.
- Content Rights saved using the previously recorded operator decision. This does not establish vendor permission beyond the existing evidence.
- Privacy policy URL saved. Data Not Collected questionnaire saved; final publication is still pending.
- Zero-price schedule configured. Mac and Apple Vision Pro availability disabled for this initial iPhone release.
- Public privacy policy and GitHub Issues support URL verified without GitHub authentication; policy matches docs/privacy-policy.md.
- Free Apps Agreement is Active. No Paid Apps Agreement was signed.

## Pending owner decisions and verification

- Owner selected trader status. DSA flow is at Contact Information Verification, before entry of public contact details. Explicit public address/phone/email approval was requested. Apple verification steps still need completion.
- Final privacy publication agreement requires explicit approval. An initial accidental draft answer was corrected, but automatic approval review requires a clear approval of the final Publish agreement.
- Worldwide availability confirmation remains pending after automatic approval review requested explicit approval for all 175 countries and future storefronts.
- App Review contact fields remain unsaved pending explicit contact-data approval. Review notes are prepared in the working browser tab, but Apple requires all contact fields before saving them.
- TestFlight visibly reports No Builds. No build has been uploaded, selected, or submitted.

## Build evidence and release limitation

- Repository HEAD: d47dcdbe6fffafabbcfbc773b785f9be166b8cdb. No source, asset, or package changes relative to the tested source commit 1ddf60cbd59ea5e5b208ea292f730fdd46fcd2fe.
- Existing gate-8 log records successful package, Simulator, archive/export, and packaged checks for version 0.1.0 build 18. Those are historical checks, not new upload or TestFlight proof.
- The exported IPA was not found in the release worktrees, inspected temporary locations, Downloads, or Xcode archive location. The log describes export to a scratch directory.
- Installed toolchain: Xcode 27.0, build 27A5218g, in Xcode-beta.app. Host macOS is 27.0 beta. No stable Xcode installation was found.
- Apple's live Xcode requirements page lists Xcode 26.6 as stable and Xcode 27 beta 6 as beta. Its submission guidance points to Xcode 26; its beta guidance identifies release candidates as suitable for submission.
- Source directly references systemExtraLargePortrait in WidgetAccountPresentation.swift, WidgetViews.swift previews, and MIK95Tests.swift. Runtime availability guards alone do not make that API compile under an older SDK.
- Owner decision requested: prepare a stable-Xcode-compatible build with compiler guards and new validation, or finish listing and wait for Xcode 27 RC. No source changes or toolchain installation undertaken pending this decision.
- Device widget/accessibility and live four-provider checks are not newly proven by this session. Processed-build TestFlight smoke testing remains outstanding.

## Apple references inspected

- https://developer.apple.com/xcode/system-requirements
- https://developer.apple.com/app-store/submitting/
- https://developer.apple.com/support/install-beta/
- https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds

No App Review submission or public release occurred.
