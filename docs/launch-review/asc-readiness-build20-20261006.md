# Build 20 preparation readiness, 2026-10-06

Worktree: `/Users/brandon/code/personal/ammo-worktrees/build-20-release`
Branch: `codex/build-20-release`
Exact base: `4da021fb0322ca3e96a4da38c216c0d256353991`

**Preparation only. Build 20 is not yet cleared for phone overinstall or
App Store upload. Stop BEFORE either action.** No build-20 iOS archive,
signed export, independent artifact review, or device result is claimed.

## Verified in this preparation

- The worktree started clean at the exact base above. PRs #48 and #49 are
  incorporated in that base, per the operator handoff.
- `Apps/iOS/project.yml` now sets `CURRENT_PROJECT_VERSION: 20` and retains
  `MARKETING_VERSION: 0.1.0`. Both tracked Info.plists reference these shared
  settings; neither contains a separate literal version requiring a bump.
- XcodeGen 2.46.0 generated the ignored `Apps/iOS/Ammo.xcodeproj`, including
  its existing post-generation package fix. Both project configurations
  contain 0.1.0 (20); all four app/widget Debug/Release configurations
  inherit those settings without a version override.
- Six app/widget plist assertions passed: build-setting reference,
  marketing-setting reference, and keychain-group prefix template in each
  bundle. Both Info.plists and both entitlements parse successfully.
- `rtk swift test --disable-sandbox` ran once and passed: **219 tests in
  24 suites**, exit 0. SwiftPM reported inaccessible user cache directories
  and a readonly manifest-cache database; these warnings did not block the
  build or tests. The XCTest wrapper reported zero tests; the counts above
  are from the successful Swift Testing run.
- `rtk git diff --check` passed with no whitespace errors.
- The host iPhone 17 Pro iOS 27.0 Simulator suite passed: **155 tests,
  zero failures**, independently confirmed from `AmmoTests.xcresult` with
  `xcresulttool get test-results summary`. The MCP transport timed out after
  five minutes, but the underlying run completed with result `Passed`.
- The tracked Info.plists, entitlements, accepted GA workflow, and build-19
  HOLD record are byte-for-byte unchanged from the exact base. No
  application behavior, credentials, or account data changed.

## Build 19 remains on HOLD

The [build-19 record](asc-readiness-build19-20260925.md) remains authoritative
for its historical artifact and HOLD. Its uploaded app/widget Info.plists
request `com.brandon.ammo.shared`, while their signed entitlements grant
`JN24JD42L3.com.brandon.ammo.shared`. Do not attach build 19 to 0.1.0 or
submit it. This preparation does not re-review that IPA or exercise the
failure on a device.

Static inspection confirms the accepted GA workflow passes
`AppIdentifierPrefix=<team_id>.` to the unsigned archive (default team
`JN24JD42L3`) and asserts the prefixed keychain group in both packaged
Info.plists. That is source evidence; its corrected runner execution and
the build-20 packaged values remain pending. No workflow change was needed.

## Pending orchestrator gates

1. Review and merge the narrow change, then dispatch the accepted GA
   workflow on the resulting exact revision with team `JN24JD42L3`.
   Retain run provenance and artifact hashes; confirm its assertions pass.
2. Handle host re-signing and export. Independently review both the archive
   and exported IPA: app and widget must be 0.1.0 (20), have the expected GA
   stamps, contain no unresolved build-setting placeholders, and request
   `JN24JD42L3.com.brandon.ammo.shared` in `AmmoKeychainAccessGroup`. In each
   signed bundle, that exact string must appear in `keychain-access-groups`;
   verify the app group, team/bundle identities, distribution entitlements,
   and signatures as well. Re-signing alone does not repair an Info.plist.
3. **Stop BEFORE any phone overinstall and BEFORE App Store upload.** The
   artifact review and an explicit operator go-ahead must precede either.
   This preparation authorizes neither action and performs neither.

Later device/provider, widget clipping, and processed-build TestFlight
checks remain open. Any eventual overinstall plan should preserve build-18
accounts and follow the build-19 HOLD record's warning against removing or
re-adding accounts in build 19. No live provider tokens were read here.

Historical listing/owner items (screenshots, trader verification, privacy
publication, availability) were not checked live. Reconcile their current
status separately; this document makes no App Store readiness claim.
