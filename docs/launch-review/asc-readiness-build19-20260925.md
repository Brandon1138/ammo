# App Store Connect readiness, build 19 — 2026-09-25

Source commit under test: `a747ab037ba7596bf031f537f98f3aca0cd49e5a`
(`main` `2dc6f1b` + build bump 18 → 19). This folds in PR #45 (MIK-251,
Codex Spark retirement) and PR #46 (MIK-252, Anthropic banked usage-limit
resets). Every number below was regenerated on this commit; nothing is
inherited from the build 18 evidence in
`gate-8-build-verification-20260827.md`.

## Verdict

**Not uploadable from this machine as it stands.** The app, listing and
screenshots are ready; the toolchain is not. One blocker, three owner items
carried over from `asc-progress-20260905.md`, nothing new on the app side.

## 1. Merge and test gates (PASS)

| Check | Result |
|---|---|
| PR #45 merged | `17a0ad3`, clean merge onto `d47dcdb` |
| PR #46 merged | `2dc6f1b`, after merging main into the branch (`bf1b2fd`) with the review's documented resolution: `UsageDisplayPreferences.swift` deleted, `UsageSnapshot.init(from:)` keeps both the Spark window filter and the `bankedResets` decode |
| `swift test --disable-sandbox` on `bf1b2fd` | **PASS** — 219 tests in 24 suites |
| AmmoTests, iPhone 17 Pro simulator, on `bf1b2fd` | **PASS** — 155 tests in 23 suites (`** TEST SUCCEEDED **`). Down from 168 because #45 deleted `MIK145Tests` and the Spark cases |
| Open PRs after merge | none |

## 2. Release / archive checks (PASS)

Same commands as gate 8 §3 and §7. `-exportArchive` was run **without**
`-allowProvisioningUpdates`; nothing in the developer account was created or
changed.

| Check | Result |
|---|---|
| Release archive, `generic/platform=iOS` | **PASS** — `** ARCHIVE SUCCEEDED **`, 0 errors |
| App Store export | **PASS** — `** EXPORT SUCCEEDED **` |
| Exported artifact | `Ammo.ipa`, sha256 `0a9e9700ab58939e0673af1108c123175f5b3908bf618756ee6fbe7695e0c585` |
| Export signing | "Cloud Managed Apple Distribution", team `JN24JD42L3`, certificate expires 2027-07-20; app and widget use the "iOS Team Store Provisioning Profile" for their bundle IDs |
| IPA entitlements | `get-task-allow` false, `beta-reports-active` true, app group `group.com.brandon.ammo`, keychain group `JN24JD42L3.com.brandon.ammo.shared` |

Note: `security find-identity` on this machine lists only "Apple Development"
and "Developer ID Application" identities. The export still succeeded because
Xcode used its cloud-managed distribution certificate. Nothing to fix, but
export requires being signed in to the Apple account in Xcode.

## 3. Packaged artifact (PASS)

Read from the archived `Ammo.app`, not from `project.yml`.

| Key | Value |
|---|---|
| `CFBundleShortVersionString` / `CFBundleVersion` | `0.1.0` / `19` (app and widget extension agree) |
| `ITSAppUsesNonExemptEncryption` | `false` |
| `MinimumOSVersion` | `18.0` |
| `DTSDKName` | `iphoneos27.0` |
| `DTXcode` / `DTXcodeBuild` | `2700` / **`27A5218g`** (see §4) |
| `PrivacyInfo.xcprivacy` | tracking false, no collected data types, no tracking domains, one accessed-API entry (UserDefaults, reason `1C8F.1`) — unchanged from build 18 |
| Leftover "Spark" strings in the binary | 2, both the retired-marker cleanup path (`codex-spark-metering-enabled` and its log line). No user-visible string. |

## 4. BLOCKER — beta toolchain and beta build machine

App Store Connect rejects an upload with ITMS-90111 "Invalid Toolchain" when
either the Xcode that built it or the macOS it was built on is a beta. Both
are true of this archive:

| Stamp in the archived `Info.plist` | Value | Status |
|---|---|---|
| `DTXcodeBuild` | `27A5218g` | Xcode 27.0 **beta**. GA is `27A266a`, shipped 2026-09-14, the day Apple opened submissions for iOS 27 SDK builds. |
| `BuildMachineOSBuild` | `26B5091g` | macOS 27.2 **beta 1** (host `sw_vers`). macOS 27.0 GA is `26A428`, shipped 2026-09-14. |

So the IPA in §2 proves the source archives and exports; it is not an
uploadable binary. This was already the standing owner decision on
2026-09-05, when only the Xcode side was known.

Required before upload, in order:

1. Install Xcode 27.0 GA (`27A266a`) from the Mac App Store or developer
   downloads. It requires macOS 26.6 or later; the host satisfies that.
2. Deal with the build-machine stamp. The host is on the macOS 27.2 beta
   track and cannot be downgraded in place, so pick one:
   - **Xcode Cloud** or any Mac on macOS 27.0 GA: archive there, stamp is
     correct by construction.
   - **Local workaround:** archive with Xcode 27.0 GA, then set
     `BuildMachineOSBuild` to `26A428` in
     `Ammo.xcarchive/Products/Applications/Ammo.app/Info.plist` (and in
     `PlugIns/AmmoWidgets.appex/Info.plist`) before `-exportArchive`. Export
     re-signs both bundles, so the edit does not break the signature. This is
     the widely used workaround for ITMS-90111 on beta hosts; it is a
     metadata edit only and changes no code.
3. Re-run §2 and §3 on the same source commit and confirm `DTXcodeBuild` is
   `27A266a` and `BuildMachineOSBuild` is `26A428`.
4. Upload (Xcode Organizer, Transporter or `xcrun altool`), wait for
   processing, then attach build 19 to version 0.1.0 in App Store Connect.

The `systemExtraLargePortrait` concern from 2026-09-05 (source compiling only
under the iOS 27 SDK) is moot with Xcode 27 GA.

## 5. Store screenshots (gate 9) — recaptured (PASS)

The build 18 Settings frame no longer matched the app: it showed the
"Display" section with "Show Codex Spark meters" (deleted by #45) and lacked
the Claude "Banked reset granted" toggle (added by #46). All four 6.9-inch
frames were recaptured from `a747ab0` on the iPhone 17 Pro Max iOS 27.0
simulator at native 1320 x 2868, via a throwaway XCUITest that was not
committed. Manifest, assertions and provenance:
`Screenshots/appstore/6.9-inch/README.md`.

Only the Settings frame changed in content. Demo mode carries no Spark meter
and no banked reset, so Usage, On-demand and History look the same as build
18. **Owner action:** replace the four screenshots in App Store Connect with
the build 19 set, in the same order (Usage, On-demand, History, Settings).

## 6. Listing metadata (no change needed)

`submission-package.md` §1 (description, keywords, promotional text, review
notes) mentions neither Spark nor banked resets. The RESET ALERTS paragraph
already describes reset notifications generically. The App Privacy answers
(Data Not Collected) are unaffected: PR #46 adds request headers on the
Claude usage call, sends no new data, and stores nothing new off-device. No
App Review Notes edit is needed.

## 7. Carried-over owner items (unverified, from `asc-progress-20260905.md`)

These live in App Store Connect and could not be checked from this machine:

- Trader status: DSA Contact Information Verification was mid-flow; public
  contact details still needed explicit approval.
- App Privacy: final "Publish" of the Data Not Collected questionnaire needed
  explicit approval.
- Availability: confirmation of all 175 countries and future storefronts.

## 8. Not verified here — operator-only

- Device overinstall of build 19 and the live four-provider check.
- Medium-widget clipping check for the banked-reset ledger row (MIK-252 L5).
- Processed-build TestFlight smoke test after the GA-toolchain upload.

## 9. Reproduce

```
cd Apps/iOS && xcodegen generate && cd ../..
swift test --disable-sandbox
xcodebuild -project Apps/iOS/Ammo.xcodeproj -scheme Ammo \
  -destination 'platform=iOS Simulator,id=<iPhone 17 Pro udid>' test
xcodebuild -project Apps/iOS/Ammo.xcodeproj -scheme Ammo -configuration Release \
  -destination 'generic/platform=iOS' -archivePath <scratch>/Ammo.xcarchive archive
xcodebuild -exportArchive -archivePath <scratch>/Ammo.xcarchive \
  -exportOptionsPlist <scratch>/ExportOptions.plist -exportPath <scratch>/export-appstore
/usr/libexec/PlistBuddy -c "Print DTXcodeBuild" <scratch>/Ammo.xcarchive/Products/Applications/Ammo.app/Info.plist
```

`ExportOptions.plist` is the gate 8 one: `method` `app-store-connect`,
`teamID` `JN24JD42L3`, `signingStyle` `automatic`, `uploadSymbols` true,
`destination` `export`.
