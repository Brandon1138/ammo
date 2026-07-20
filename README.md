# AMMO

How much ammo do you have left? iOS widgets for your AI coding usage limits —
Claude Code, Codex, and Cursor now; Antigravity planned.

**No server. No stranger's OAuth app. Your tokens stay in your Keychain, on your
device, in an app you built.**

This repo doubles as a DIY kit: [SPEC.md](SPEC.md) contains everything needed to
rebuild Ammo from scratch with a coding agent — verified API contracts, auth flows,
architecture — so you never have to trust anyone else's binary with your accounts.

## Status

- [x] `UsageKit` — provider adapters for Claude, Codex, and Cursor
- [x] `ammo-harness` — macOS CLI proving the data layer end-to-end
- [x] iOS app (onboarding, shared 60-second fetch gate, adaptive background refresh)
- [x] WidgetKit widgets (home screen + lock screen, direct throttled refresh)
- [ ] macOS menu bar app (stretch)

## Quick start

```sh
swift test                 # offline decode tests
swift run ammo-harness     # live usage bars in your terminal (needs logged-in CLIs)

# iOS app (needs Xcode 16+ and `brew install xcodegen`):
cd Apps/iOS && xcodegen && open Ammo.xcodeproj
# select your team under Signing & Capabilities → run on your iPhone
```
