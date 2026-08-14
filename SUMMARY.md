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
