# AMMO

How much ammo do you have left? An iOS app and widgets for included limits and
on-demand capacity across Claude Code, Codex, Cursor, and OpenRouter.

**No Ammo backend. Provider tokens stay in this device's Keychain and requests
go directly to each provider.**

Source and architecture are published for inspection. [SPEC.md](SPEC.md) documents
provider contracts, auth flows, storage boundaries, and build steps.

Credentials use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: they do not
sync through iCloud Keychain or transfer to a replacement device. Re-add accounts
after restoring onto a new device.

## Status

- [x] `UsageKit` — provider adapters for Claude, Codex, Cursor, and OpenRouter
- [x] `ammo-harness` — macOS CLI proving the data layer end-to-end
- [x] iOS app (Usage, On-demand, History, onboarding, and adaptive refresh)
- [x] WidgetKit widgets (current limits, daily activity, and lock-screen gauges)
- [ ] macOS menu bar app (stretch)

## Quick start

```sh
swift test                 # offline decode tests
swift run ammo-harness     # live usage bars in your terminal (needs logged-in CLIs)

# iOS app (needs Xcode 16+ and `brew install xcodegen`):
cd Apps/iOS && xcodegen && open Ammo.xcodeproj
# select your team under Signing & Capabilities → run on your iPhone
```
