# Ammo App Store screenshots

## Size class

Modern App Store Connect iPhone submission target: 6.9-inch class, portrait
1320 x 2868 px. The installed iPhone 17 Pro Max simulators represent this
class on iOS 26.5 and iOS 27.0. Captures below use iPhone 17 Pro Max on iOS
27.0, UDID `373491EF-27BF-47DE-AD44-3FF77675C8FC`.

The older 6.5-inch set is 1284 x 2778 px and is not included because this task
targets the current 6.9-inch requirement.

## Manifest

Native-resolution PNG requirement: every deliverable must be captured directly
at 1320 x 2868. Former sips-upscaled files were deleted and must not be
restored.

| File | Device | Resolution | Content |
| --- | --- | --- | --- |
| `ammo-6.9-inch-build19-01-usage.png` | iPhone 17 Pro Max, iOS 27.0 | 1320 x 2868 native | Usage tab with Codex, Claude, and Cursor sample accounts |
| `ammo-6.9-inch-build19-02-on-demand.png` | iPhone 17 Pro Max, iOS 27.0 | 1320 x 2868 native | On-demand tab with sample personal limits, under the shared header |
| `ammo-6.9-inch-build19-03-history.png` | iPhone 17 Pro Max, iOS 27.0 | 1320 x 2868 native | History tab with sample weekly activity heatmap and chart, under the shared header |
| `ammo-6.9-inch-build19-04-settings.png` | iPhone 17 Pro Max, iOS 27.0 | 1320 x 2868 native | Settings sheet: notification toggles per provider, including the Claude "Banked reset granted" toggle |

The build 18 set (`ammo-6.9-inch-build18-01…04.png`, captured from `1ddf60c`)
was removed with this set. Its Settings frame showed the "Display" section
with the "Show Codex Spark meters" toggle that PR #45 deleted, and lacked the
Claude "Banked reset granted" toggle that PR #46 added, so it no longer
matched the shipping app. Git history still holds it.

## Capture and privacy notes

- Captured from source commit `a747ab037ba7596bf031f537f98f3aca0cd49e5a`
  (`MARKETING_VERSION` 0.1.0, `CURRENT_PROJECT_VERSION` 19), the source-only
  commit of this branch, after `xcodegen generate` and a Debug
  `iphonesimulator` build of the `Ammo` scheme driven by a throwaway XCUITest
  target that was never committed. The test tapped **See a demo**, walked the
  three tabs, opened Settings, asserted on each frame that the `Settings`
  button, the `Ammo`-labelled logo and `Exit Demo` were present, asserted that
  Settings shows two "Banked reset granted" switches and no "Display" section,
  and wrote `XCUIScreen.main.screenshot()` to disk unmodified. The
  docs-and-screenshots commit that carries these files does not touch source,
  so it cannot change what they show.
- Demo mode supplied every visible account and data point, entered by tapping
  **See a demo** in the empty state. No credentials, network requests, real
  account files, token, personal label, or account identifier appears in the
  set.
- Status bar was normalised with
  `xcrun simctl status_bar <udid> override --time 9:41 --dataNetwork wifi
  --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4
  --batteryState charged --batteryLevel 100`.
- App locale was pinned to `en_US` for capture via the standard
  `-AppleLocale`/`-AppleLanguages` launch arguments, so currency renders as
  `$82.00` rather than the host machine's Romanian regional format.
- Screenshots are unretouched full-resolution frames of the running app. No
  cropping, resizing, compositing, or device framing was applied.
- Widget capture is still missing: Ammo has no widget already placed on the
  simulator Home Screen and system Home Screen widget placement is not
  reachable from the automation bridge. A widget shot, if wanted, is a device
  capture task.

## Build 19 recapture (`a747ab0`, 2026-09-25)

All four frames were recaptured because build 19 folds in PR #45 and PR #46.
Only the Settings frame changed in content: the Claude group gained a
"Banked reset granted" toggle and the "Display" section is gone. Usage,
On-demand and History are visually the same as the build 18 frames; the Usage
and History bytes differ only through the "Updated N sec ago" stamp and the
date-relative history axis, and the On-demand frame came out byte-identical to
its build 18 predecessor. Demo mode carries no Spark meter and no banked
reset, so neither PR changes the Usage frame.

Evidence log: `docs/launch-review/asc-readiness-build19-20260925.md`.

## Shared header (build 18, `1ddf60c`)

All four frames were re-captured because Usage, On-demand, and History now draw
one compact top bar: Settings gear leading, Ammo logo centred, Add Account
trailing — `Exit Demo` in place of Add Account while the demo is on. The
previous build 18 frames of the same filenames showed a large `On-demand` /
`History` title and no toolbar on those two tabs. Filenames are unchanged so
nothing downstream has to be re-pointed.

Three of the four changed on disk. `04-settings.png` came out byte-identical to
its predecessor — the Settings sheet renders nothing time-dependent — so git
shows no change to that one file even though it was captured from `1ddf60c` with
the rest.

The capture run asserted on each of the three tabs that Settings, the
`Ammo`-labelled logo, and `Exit Demo` are present and that no large typed title
remains, and passed on all three.

Evidence log: `docs/launch-review/gate-8-build-verification-20260827.md`.
