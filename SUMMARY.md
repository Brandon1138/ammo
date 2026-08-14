# Settings and notification preferences UI

## Changes

- Added `Sources/UsageKit/Notifications/NotificationPreferences.swift` with the byte-fixed shared contract supplied in the task.
- Added `NotificationPreferencesStorage`, which JSON-encodes preferences under `NotificationPreferences.storageKey` in an injected `UserDefaults` store.
- Added UI-independent package tests covering persistence round-trip plus missing/corrupt-data fallback.
- Added `NotificationSettingsModel`, an app-only `@Observable` authorization and persistence wrapper. The app uses the existing `group.com.brandon.ammo` App Group defaults suite, falling back to `.standard`.
- Added a native SwiftUI `SettingsView` with master notification authorization and disabled per-provider toggles for Codex, Claude, and Cursor.
- Added a leading `gearshape` toolbar button to Usage. It uses the same native toolbar label/chrome as the trailing `plus` menu and mirrors its placement around the centered Ammo wordmark.
- Consolidated Usage modal state into one item-driven `UsageSheet` for Settings and provider onboarding.

## Authorization behavior

- First enable checks current settings and requests `.alert`, `.sound`, and `.badge` authorization when status is `.notDetermined`.
- Authorized, provisional, and ephemeral status enables the persisted master preference.
- Denied or still-undetermined status keeps master off.
- Denied status shows an inline explanation and `Open System Settings` button using `UIApplication.openSettingsURLString`.
- Settings re-checks authorization when opened and whenever scene returns active. A newly denied system permission forces persisted master off.
- Turning app master off does not alter individual provider selections.
- No notification scheduling or reset detection was added.

## Verification

- `swift build --disable-sandbox`: passed.
- `swift test --disable-sandbox`: passed, 68 tests across 14 suites, including both new persistence tests.
- XcodeGen project regeneration: passed.
- iPhoneOS UsageKit module emission: passed.
- iPhoneOS full app/shared source typecheck with `swiftc -typecheck -disable-sandbox`: passed.
- `git diff --check`: passed.

## Sandbox limits

- `xcodebuild` Simulator and generic-device attempts stopped before source compilation because CoreSimulatorService disconnected and process received signal 15. Simulator rendering and full Xcode target build were not verified.
- Cyberdeck CLI reporting failed with `connect EPERM /tmp/cyberdeck-501.sock`.
- Commit failed because sandbox could not create `/Users/brandon/code/personal/ammo/.git/worktrees/settings-notifications-ui/index.lock`. All changes remain unstaged in this worktree for orchestrator commit.

---

# Notification engine handoff

Commit could not be created because the sandbox cannot write the parent repository's worktree metadata:

```text
fatal: Unable to create '/Users/brandon/code/personal/ammo/.git/worktrees/notification-engine/index.lock': Operation not permitted
```

Suggested commit message: `feat: add usage reset notification engine`

## Files

- `Sources/UsageKit/Notifications/NotificationPreferences.swift`: exact shared preferences contract.
- `Sources/UsageKit/Notifications/NotificationEngine.swift`: pure planner, Claude session idle state, spontaneous-reset detection, banked-reset differ, stable schedule IDs, cancellation commands, stale-poll protection, persisted dedupe state.
- `Sources/UsageKit/Notifications/LocalNotificationCenter.swift`: delivery protocol.
- `Apps/iOS/Ammo/Services/UsageNotificationService.swift`: `UNUserNotificationCenter` adapter, authorization no-op, per-pass preferences reload, UserDefaults state persistence, command execution.
- `Apps/iOS/Ammo/Models/AccountStore.swift`: runs notification pass after app refreshes. Existing foreground, manual, account-add, and `BGAppRefreshTask` paths all converge here.
- `Tests/UsageKitTests/NotificationEngineTests.swift`: 15 notification-engine tests.

## Persisted state

UserDefaults key `ammo.notificationEngineState`, JSON-encoded `NotificationEngineState`:

- `lastSnapshots: [String: UsageSnapshot]`
- `claudeSessionObservations: [String: ClaudeSessionObservation]`, containing reset instant and whether usage was observed in that window
- `lastFiredMarkers: [String: String]`, keyed by notification type plus account

Preferences are JSON-decoded from `UserDefaults.standard` key `ammo.notificationPreferences` on every pass. Existing codebase has no app-group UserDefaults suite.

## Verification

- `swift build --disable-sandbox`: passed.
- `swift test --disable-sandbox`: passed, 81 tests in 14 suites; 15 notification-engine tests.
- iPhoneOS Swift typecheck of UsageKit module: passed.
- iPhoneOS Swift typecheck of `UsageNotificationService` plus logger: passed.
- `git diff --check`: passed.
- Full `xcodebuild`: unavailable because sandbox killed Xcode/CoreSimulator access and blocked DerivedData outside writable roots. Generated project itself succeeded.
- Live notification authorization, scheduling, and iOS background delivery remain unverified in sandbox.
- `cyberdeck event submit`: unavailable with `connect EPERM /tmp/cyberdeck-501.sock`.
