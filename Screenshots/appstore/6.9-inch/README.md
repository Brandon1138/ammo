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
| `ammo-6.9-inch-build18-01-usage.png` | iPhone 17 Pro Max, iOS 27.0 | 1320 x 2868 native | Usage tab with Codex, Claude, and Cursor sample accounts |
| `ammo-6.9-inch-build18-02-on-demand.png` | iPhone 17 Pro Max, iOS 27.0 | 1320 x 2868 native | On-demand tab with sample personal limits, under the shared header |
| `ammo-6.9-inch-build18-03-history.png` | iPhone 17 Pro Max, iOS 27.0 | 1320 x 2868 native | History tab with sample weekly activity heatmap and chart, under the shared header |
| `ammo-6.9-inch-build18-04-settings.png` | iPhone 17 Pro Max, iOS 27.0 | 1320 x 2868 native | Settings sheet: notification toggles per provider |

The previous unversioned set (`01-usage.png` … `04-settings.png`) was captured
from `a7fc5d54c045db0c630d5fe006bd68e3917b55c6`, before build 18 and before the
Settings About section landed. It is superseded by the build 18 set above and
was removed so no stale capture can be uploaded by mistake. Git history still
holds it.

## Capture and privacy notes

- Captured from source commit `1ddf60cbd59ea5e5b208ea292f730fdd46fcd2fe`
  (`MARKETING_VERSION` 0.1.0, `CURRENT_PROJECT_VERSION` 18), the source-only
  commit of this branch, after `xcodegen generate` and a Release
  `iphonesimulator` build of the `Ammo` scheme. The docs-and-screenshots commit
  that carries these files does not touch source, so it cannot change what they
  show.
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
