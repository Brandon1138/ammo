# AMMO

How much ammo do you have left? An iOS app and widgets for included limits and
on-demand capacity across Claude Code, Codex, and Cursor; Antigravity planned.

**No server. No stranger's OAuth app. Your tokens stay in your Keychain, on your
device, in an app you built.**

This repo doubles as a DIY kit: [SPEC.md](SPEC.md) contains everything needed to
rebuild Ammo from scratch with a coding agent — verified API contracts, auth flows,
architecture — so you never have to trust anyone else's binary with your accounts.

## Status

- [x] `UsageKit` — provider adapters for Claude, Codex, and Cursor
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
