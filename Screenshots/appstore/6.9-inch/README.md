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
with `xcrun simctl io` at 1320 x 2868. Former sips-upscaled files were deleted
and must not be restored.

| File | Device | Resolution | Content |
| --- | --- | --- | --- |
| `01-usage.png` | iPhone 17 Pro Max, iOS 27.0 | 1320 x 2868 native | Usage tab with Codex, Claude, and Cursor sample accounts |
| `02-on-demand.png` | iPhone 17 Pro Max, iOS 27.0 | 1320 x 2868 native | On-demand tab with sample personal limits |
| `03-history.png` | iPhone 17 Pro Max, iOS 27.0 | 1320 x 2868 native | History tab with sample weekly activity heatmap and chart |
| `04-settings.png` | iPhone 17 Pro Max, iOS 27.0 | 1320 x 2868 native | Settings Privacy & Support disclosure surface |

## Capture and privacy notes

- Captured from App Store readiness candidate
  `a7fc5d54c045db0c630d5fe006bd68e3917b55c6` after XcodeGen, 208 SwiftPM
  tests, 161 Simulator tests, and a successful Simulator build-and-run.
- Demo mode supplied every visible account and data point. No credentials,
  network requests, real account files, token, personal label, or account
  identifier appears in the set.
- Every PNG was captured directly with
  `xcrun simctl io 373491EF-27BF-47DE-AD44-3FF77675C8FC screenshot`; no
  resizing or upscaling was performed.
- Widget capture was attempted by returning to the simulator Home Screen.
  Ammo had no widget already placed, and system Home Screen widget placement
  was unavailable through the simulator automation bridge, so no widget file
  is included.
