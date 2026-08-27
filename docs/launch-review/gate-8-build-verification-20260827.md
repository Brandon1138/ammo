# Gate 8 build verification — 2026-08-27

Evidence log for `docs/launch-review/submission-package.md` §5 gates 8 and 9.
Everything below was run on **2026-08-27** against one commit and one commit
only.

**Source commit under test:** `1ddf60cbd59ea5e5b208ea292f730fdd46fcd2fe`
(`feat(ui): give every tab the same compact Ammo header`) — the tip of
`unify-tab-header-20260827`, itself cut from
`7ff1837c5f7bd0c0d0793573fa11ffd612b11499`
(`Merge pull request #43 from Brandon1138/appstore-gates-20260827`).
`MARKETING_VERSION` 0.1.0, `CURRENT_PROJECT_VERSION` 18, both unchanged by that
commit.

**Why this log was re-run.** The previous edition of this file verified
`b8e19b71affef8a97b781c242592cd0de9704213` and stated that any later source
change voids it. `1ddf60c` is a source change — it unifies the Usage, On-demand,
and History top chrome — so every §1–§5 result below was produced again, from
that one commit, and nothing is carried over.

**This PR's two commits.** `1ddf60c` is source only: five Swift files, no
`project.yml`, no asset, no package manifest, no build number. The commit that
follows it changes **only** this file and the four PNGs plus README under
`Screenshots/appstore/6.9-inch/`, so it cannot alter the binary or the captures
described here — the artifact verified below is bit-for-bit what `main` produces
after this PR merges. If any further source lands on `main` afterwards, every
result below is void and gate 8 must be re-run.

**Toolchain.**

| Tool | Version |
|---|---|
| Xcode | 27.0 (27A5218g) |
| Swift | 6.4 (swiftlang-6.4.0.25.4, clang-2100.3.25.1) |
| XcodeGen | 2.46.0 |
| Simulator | iPhone 17 Pro Max, iOS 27.0, UDID `373491EF-27BF-47DE-AD44-3FF77675C8FC` |

**Project generation.** `Apps/iOS/Ammo.xcodeproj` is gitignored and was
regenerated with `xcodegen generate` in `Apps/iOS` before every Xcode
invocation below (`postGenCommand: ./Scripts/fix-local-package-products.sh` ran
as configured). **PASS.**

The four check families are kept separate on purpose: a package-level pass says
nothing about the app target, a Simulator pass says nothing about a Release
archive, and an archive pass says nothing about what is actually packaged in the
uploadable artifact.

---

## 1. Source / package checks (SwiftPM)

Command (the `--disable-sandbox` flag is a requirement of the worker
environment, not of the package):

```
swift test --disable-sandbox
```

| Check | Result |
|---|---|
| `swift build` of `UsageKit`, `ammo-harness`, `UsageKitTests` | **PASS** |
| Swift Testing run | **PASS** — `Test run with 208 tests in 24 suites passed after 0.088 seconds` |
| XCTest bundle | 0 tests executed (`Executed 0 tests, with 0 failures (0 unexpected)`) — expected; the suite is Swift Testing throughout, not XCTest |
| Failures | none |

## 2. Simulator checks (app + widget targets)

```
xcodebuild -project Apps/iOS/Ammo.xcodeproj -scheme Ammo \
  -destination 'platform=iOS Simulator,id=373491EF-27BF-47DE-AD44-3FF77675C8FC' test
```

| Check | Result |
|---|---|
| Build of `Ammo`, `AmmoWidgets`, `AmmoTests` for the Simulator | **PASS** |
| Swift Testing run | **PASS** — `Test run with 168 tests in 24 suites passed after 4.786 seconds` |
| xcodebuild verdict | **PASS** — `** TEST SUCCEEDED **` |
| Failures | none |

The count differs from §1 (168 vs 208) because the app-target test bundle runs a
subset of the package suites plus the app-only suites; both runs are green. It
also differs from the previous edition of this log (168 in 24 suites, was 166 in
23) by exactly the two tests in the one suite `1ddf60c` adds,
`TabHeaderConsistencyTests`, which pin the shared header's demo-mode trailing
action and its single sheet route.

## 3. Release / archive checks

```
xcodebuild -project Apps/iOS/Ammo.xcodeproj -scheme Ammo \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath <scratch>/Ammo.xcarchive archive

xcodebuild -exportArchive -archivePath <scratch>/Ammo.xcarchive \
  -exportOptionsPlist <scratch>/ExportOptions.plist \
  -exportPath <scratch>/export-appstore
```

`ExportOptions.plist`: `method` `app-store-connect`, `teamID` `JN24JD42L3`,
`signingStyle` `automatic`, `uploadSymbols` true, `destination` `export`.

| Check | Result |
|---|---|
| Release archive for `generic/platform=iOS` | **PASS** — `** ARCHIVE SUCCEEDED **` |
| App Store export | **PASS** — `** EXPORT SUCCEEDED **` |
| Exported artifact | `Ammo.ipa`, 8,608,202 bytes, `sha256 a9143242cbab718b318824184512ebf018cd156690ba07d87b12c84dfbdd2ec1` |

**Signing identity differs between the two artifacts, and this matters.**

- The **archive** is signed `Apple Development: Brandon Aron (8Q2PL752G5)` via
  the "iOS Team Provisioning Profile: com.brandon.ammo" — development signing.
- The **exported IPA** is signed `Apple Distribution: Brandon Aron (JN24JD42L3)`
  — App Store distribution signing.

`-exportArchive` was deliberately run **without** `-allowProvisioningUpdates`, so
nothing was created or mutated in the Apple Developer account; export re-signed
with the distribution identity already present on this machine. The IPA, not the
archive, is the artifact whose signing state matches what App Store Connect
receives.

## 4. Artifact checks (what is actually packaged)

Read out of the built products with `codesign -d --entitlements`, `PlistBuddy`,
and `plutil` — not from `project.yml`.

### 4.1 Entitlements

| Bundle | Artifact | App group | Keychain group | Team | `get-task-allow` | Result |
|---|---|---|---|---|---|---|
| `Ammo.app` | archive | `group.com.brandon.ammo` | `JN24JD42L3.com.brandon.ammo.shared` | `JN24JD42L3` | `true` | **PASS (development-signed)** |
| `AmmoWidgets.appex` | archive | `group.com.brandon.ammo` | `JN24JD42L3.com.brandon.ammo.shared` | `JN24JD42L3` | `true` | **PASS (development-signed)** |
| `Ammo.app` | exported IPA | `group.com.brandon.ammo` | `JN24JD42L3.com.brandon.ammo.shared` | `JN24JD42L3` | `false` | **PASS (distribution-signed)** |
| `AmmoWidgets.appex` | exported IPA | `group.com.brandon.ammo` | `JN24JD42L3.com.brandon.ammo.shared` | `JN24JD42L3` | `false` | **PASS (distribution-signed)** |

Both IPA bundles additionally carry `beta-reports-active = true`, which is what
an App Store / TestFlight distribution profile is expected to produce.
`application-identifier` is `JN24JD42L3.com.brandon.ammo` for the app and
`JN24JD42L3.com.brandon.ammo.widgets` for the extension. No unexpected
entitlement is present in either bundle.

### 4.2 App `Info.plist`

| Key | Archive | Exported IPA | Result |
|---|---|---|---|
| `ITSAppUsesNonExemptEncryption` | `false` | `false` | **PASS** |
| `CFBundleShortVersionString` | `0.1.0` | `0.1.0` | **PASS** |
| `CFBundleVersion` | `18` | `18` | **PASS** |

### 4.3 Privacy manifests

Both packaged `PrivacyInfo.xcprivacy` files were read out of the built bundles
(`Payload/Ammo.app/PrivacyInfo.xcprivacy` and
`Payload/Ammo.app/PlugIns/AmmoWidgets.appex/PrivacyInfo.xcprivacy`), and the
same two files were checked inside the archive.

| Bundle | `NSPrivacyAccessedAPICategoryUserDefaults` | Reason | `NSPrivacyTracking` | `NSPrivacyCollectedDataTypes` | Result |
|---|---|---|---|---|---|
| `Ammo.app` | declared | `1C8F.1` | `false` | `[]` | **PASS** |
| `AmmoWidgets.appex` | declared | `1C8F.1` | `false` | `[]` | **PASS** |

`1C8F.1` is the app-group shared-container reason, which is the one Ammo's
`UserDefaults(suiteName: "group.com.brandon.ammo")` usage requires. This is the
declaration that answers an `ITMS-91053` warning at upload time.

### 4.4 Summary

18 of 18 artifact-level checks pass. No check in §§1–4 failed, and no tool or
environment failure occurred during them.

---

## 5. App Store screenshots (gate 9)

Captured from the **same source commit**, `1ddf60cbd59ea5e5b208ea292f730fdd46fcd2fe`,
from a Release `iphonesimulator` build of the `Ammo` scheme installed on iPhone
17 Pro Max, iOS 27.0 (UDID `373491EF-27BF-47DE-AD44-3FF77675C8FC`). The app was
uninstalled first, so the empty state — and therefore **See a demo** — was
reached from a genuinely clean install rather than from a leftover marker.

**Method.** Status bar normalised with
`xcrun simctl status_bar <udid> override --time 9:41 --dataNetwork wifi
--wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4
--batteryState charged --batteryLevel 100`; carrier text is not shown on this
device class, so no carrier string appears. Demo mode was entered by tapping
**See a demo** in the app's own empty state (the stale demo marker left by the
§2 test run was removed first, so the empty state was reached genuinely). Locale
was pinned to `en_US` with the standard `-AppleLocale` / `-AppleLanguages`
launch arguments, so currency renders `$82.00` rather than the host machine's
Romanian regional format. Taps were driven by a throwaway XCUITest bundle kept
entirely outside this repository, in a scratch directory; nothing was added to
the project to make the capture possible. Frames are unretouched
`XCUIScreen.main.screenshot()` output — no cropping, resizing, upscaling,
compositing, or device framing.

**Header assertions ran with the capture.** The same throwaway bundle asserted,
on Usage *and* On-demand *and* History before each frame, that the Settings
button, the `Ammo`-labelled logo, and the demo-mode `Exit Demo` action all exist,
and that no navigation bar still draws a large typed `Usage`, `On-demand`, or
`History` title. All three screens passed; the run reported
`** TEST SUCCEEDED **`. The frames below are what those assertions saw.

**Files**, all in `Screenshots/appstore/6.9-inch/`, all verified with
`sips -g pixelWidth -g pixelHeight`:

| File | Dimensions | Portrait | Screen |
|---|---|---|---|
| `ammo-6.9-inch-build18-01-usage.png` | 1320 x 2868 | yes | Usage — shared header, Codex / Claude / Cursor sample accounts |
| `ammo-6.9-inch-build18-02-on-demand.png` | 1320 x 2868 | yes | On-demand — shared header, sample personal limits |
| `ammo-6.9-inch-build18-03-history.png` | 1320 x 2868 | yes | History — shared header, sample weekly activity heatmap and chart |
| `ammo-6.9-inch-build18-04-settings.png` | 1320 x 2868 | yes | Settings sheet — per-provider notification toggles |

All four were re-captured and written over the build 18 files of the same name
captured from `b8e19b71affef8a97b781c242592cd0de9704213`. The filenames are
unchanged. On-demand and History now show the same compact chrome as Usage —
gear, Ammo logo, `Exit Demo` while the demo is on — where they previously showed
a large `On-demand` / `History` title and no toolbar at all.

Three of the four changed on disk; the fourth did not. The new
`ammo-6.9-inch-build18-04-settings.png` came out **byte-identical** to the
committed one (blob `b9921d35dc84b63e7411324d2ee00b57537b8ec8`), because the
Settings sheet renders nothing time-dependent, so git records no change to it.
It was captured from `1ddf60c` all the same. `01-usage.png` differs only in its
relative "Updated N sec ago" line.

`sips` verification: **4 of 4 PASS**, exactly 1320 x 2868 portrait PNG each.

**Privacy check: PASS.** Every visible account is a demo fixture
(`Codex sample`, `Claude sample`, `Cursor sample`, `OpenRouter sample`), each
tagged "Sample data" by the app itself. No credential, token, real account
label, personal identifier, or unrelated device bezel appears. No network
request is made in demo mode.

**Superseded set removed.** The previous `01-usage.png` … `04-settings.png` in
the same directory were captured from
`a7fc5d54c045db0c630d5fe006bd68e3917b55c6`, before build 18 and before the
Settings About section landed. They were deleted so the wrong set cannot be
uploaded; git history retains them.

**Settings is a sheet, not a tab.** Ammo's tab bar has three tabs (Usage,
On-demand, History); Settings opens from the gear button in the shared leading
toolbar, which as of `1ddf60c` is present on all three tabs rather than on Usage
alone. The fourth screenshot is that sheet presented over Usage, as before.

---

## 6. Not verified here — operator-only

These are gate-8 items this log deliberately does **not** claim:

1. **Physical-device pass**, which carries the widget and accessibility checks
   with it. Everything above is Simulator plus a generic-iOS archive; no build
   was installed on hardware. Two checks belong to that one pass and are
   likewise unverified here: **widget on a real Home Screen** — the widget is
   only verified above as a packaged, entitled, privacy-manifested `.appex` in
   §4, never placed — and the **accessibility sweep** (Dynamic Type, VoiceOver,
   contrast).
2. **Live four-provider contract check.** No real Claude, Codex, Cursor, or
   OpenRouter credential was used; every screen in §5 is demo fixture data, and
   no provider endpoint was contacted.
3. **App Store Connect build-number query.** Build 18 is what this commit
   produces; whether 18 is still free in App Store Connect is unknown here.
4. **Upload.** Nothing was uploaded to App Store Connect. The IPA in §3 was
   exported to a scratch directory outside the repository and is not committed.

---

## 7. Reproduce

```
cd Apps/iOS && xcodegen generate && cd ../..
swift test --disable-sandbox
xcodebuild -project Apps/iOS/Ammo.xcodeproj -scheme Ammo \
  -destination 'platform=iOS Simulator,id=<iPhone 17 Pro Max udid>' test
xcodebuild -project Apps/iOS/Ammo.xcodeproj -scheme Ammo -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/Ammo.xcarchive archive
xcodebuild -exportArchive -archivePath /tmp/Ammo.xcarchive \
  -exportOptionsPlist /tmp/ExportOptions.plist -exportPath /tmp/export-appstore
unzip -q /tmp/export-appstore/Ammo.ipa -d /tmp/ipa-unzip
codesign -d --entitlements :- /tmp/ipa-unzip/Payload/Ammo.app
plutil -p /tmp/ipa-unzip/Payload/Ammo.app/PrivacyInfo.xcprivacy
```

Re-run all of it on any new release-candidate commit. Reuse no proof above.
This edition is itself an instance of that rule: `1ddf60c` changed source, so
every number above was regenerated rather than inherited.
