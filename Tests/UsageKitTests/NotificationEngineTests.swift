import Foundation
import Testing
@testable import UsageKit

@Suite struct NotificationEngineTests {
    private let accountID = "11111111-1111-1111-1111-111111111111"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func deterministicResetUsesStableIdentifierAndReplacesDate() throws {
        let firstReset = now.addingTimeInterval(6 * 86_400)
        let first = evaluate(
            current: snapshot(.codex, weeklyUsed: 40, weeklyReset: firstReset),
            preferences: enabledPreferences()
        )
        let firstRequest = try #require(first.request(type: .codexWeeklyReset))

        let secondReset = now.addingTimeInterval(7 * 86_400)
        let second = evaluate(
            current: snapshot(
                .codex,
                weeklyUsed: 0,
                weeklyReset: secondReset,
                fetchedAt: now.addingTimeInterval(60)
            ),
            preferences: enabledPreferences(),
            state: first.state
        )
        let secondRequest = try #require(second.request(type: .codexWeeklyReset))

        #expect(firstRequest.identifier == secondRequest.identifier)
        #expect(firstRequest.deliverAt == firstReset)
        #expect(secondRequest.deliverAt == secondReset)
    }

    @Test func claudeWeeklyAndCursorMonthlyResetsSchedule() {
        let reset = now.addingTimeInterval(10 * 86_400)
        let claude = evaluate(
            current: snapshot(.claude, weeklyUsed: 20, weeklyReset: reset),
            preferences: enabledPreferences()
        )
        let cursor = evaluate(
            current: snapshot(.cursor, weeklyUsed: 20, weeklyReset: reset),
            preferences: enabledPreferences()
        )

        #expect(claude.request(type: .claudeWeeklyReset)?.deliverAt == reset)
        #expect(cursor.request(type: .cursorMonthlyReset)?.deliverAt == reset)
    }

    @Test func pastDeterministicResetCancelsStableRequest() {
        let result = evaluate(
            current: snapshot(
                .cursor,
                weeklyUsed: 20,
                weeklyReset: now.addingTimeInterval(-1)
            ),
            preferences: enabledPreferences()
        )

        #expect(result.commands.contains(.cancelIdentifier(
            "ammo.notification.cursorMonthlyReset.\(accountID)"
        )))
        #expect(result.request(type: .cursorMonthlyReset) == nil)
    }

    @Test func disabledTypeCancelsEveryPendingNotificationOfThatType() {
        var preferences = enabledPreferences()
        preferences.codexWeeklyReset = false

        let result = evaluate(
            current: snapshot(
                .codex,
                weeklyUsed: 40,
                weeklyReset: now.addingTimeInterval(86_400)
            ),
            preferences: preferences
        )

        #expect(result.commands.contains(.cancelType(.codexWeeklyReset)))
        #expect(result.request(type: .codexWeeklyReset) == nil)
    }

    @Test func masterDisabledCancelsAllTypesAndAdvancesBaseline() {
        let previous = snapshot(
            .codex,
            weeklyUsed: 60,
            weeklyReset: now.addingTimeInterval(6 * 86_400),
            fetchedAt: now.addingTimeInterval(-300)
        )
        let current = snapshot(
            .codex,
            weeklyUsed: 0,
            weeklyReset: now.addingTimeInterval(7 * 86_400)
        )
        var state = NotificationEngineState()
        state.lastSnapshots[accountID] = previous

        let result = evaluate(
            current: current,
            preferences: .default,
            state: state
        )

        #expect(result.commands.count == UsageNotificationType.allCases.count)
        #expect(result.commands.allSatisfy {
            if case .cancelType = $0 { true } else { false }
        })
        #expect(result.state.lastSnapshots[accountID] == current)
    }

    @Test func staleOverlappingPollCannotRollStateBackwardOrFire() {
        let latest = snapshot(
            .codex,
            weeklyUsed: 40,
            weeklyReset: now.addingTimeInterval(7 * 86_400),
            banked: 2,
            fetchedAt: now
        )
        var state = NotificationEngineState(lastSnapshots: [accountID: latest])
        state.claudeSessionObservations[accountID] = ClaudeSessionObservation(
            resetAt: now.addingTimeInterval(60 * 60),
            observedUsage: true
        )
        let stale = snapshot(
            .codex,
            weeklyUsed: 0,
            weeklyReset: now.addingTimeInterval(6 * 86_400),
            banked: 3,
            fetchedAt: now.addingTimeInterval(-60)
        )

        let result = evaluate(
            current: stale,
            preferences: enabledPreferences(),
            state: state
        )

        #expect(result.state == state)
        #expect(result.commands.isEmpty)
    }

    @Test func claudeSessionStopsAfter2300ResetWhileIdleThenRearmsOnUsage() throws {
        let preferences = enabledPreferences()
        let reset2300 = now.addingTimeInterval(60 * 60)
        let activeWindow = evaluate(
            current: snapshot(
                .claude,
                weeklyUsed: 30,
                weeklyReset: now.addingTimeInterval(4 * 86_400),
                sessionUsed: 35,
                sessionReset: reset2300
            ),
            preferences: preferences
        )
        #expect(activeWindow.request(type: .claudeSessionReset)?.deliverAt == reset2300)

        let after2300 = now.addingTimeInterval(65 * 60)
        let reset0400 = reset2300.addingTimeInterval(5 * 60 * 60)
        let firstIdleWindow = evaluate(
            current: snapshot(
                .claude,
                weeklyUsed: 30,
                weeklyReset: now.addingTimeInterval(4 * 86_400),
                sessionUsed: 0,
                sessionReset: reset0400,
                fetchedAt: after2300
            ),
            preferences: preferences,
            state: activeWindow.state,
            at: after2300
        )
        #expect(firstIdleWindow.request(type: .claudeSessionReset) == nil)
        #expect(firstIdleWindow.commands.contains(.cancelIdentifier(
            "ammo.notification.claudeSessionReset.\(accountID)"
        )))

        let after0400 = reset0400.addingTimeInterval(5 * 60)
        let reset0900 = reset0400.addingTimeInterval(5 * 60 * 60)
        let secondIdleWindow = evaluate(
            current: snapshot(
                .claude,
                weeklyUsed: 30,
                weeklyReset: now.addingTimeInterval(4 * 86_400),
                sessionUsed: 0,
                sessionReset: reset0900,
                fetchedAt: after0400
            ),
            preferences: preferences,
            state: firstIdleWindow.state,
            at: after0400
        )
        #expect(secondIdleWindow.request(type: .claudeSessionReset) == nil)

        let usedAgain = reset0900.addingTimeInterval(-60 * 60)
        let rearmed = evaluate(
            current: snapshot(
                .claude,
                weeklyUsed: 31,
                weeklyReset: now.addingTimeInterval(4 * 86_400),
                sessionUsed: 8,
                sessionReset: reset0900,
                fetchedAt: usedAgain
            ),
            preferences: preferences,
            state: secondIdleWindow.state,
            at: usedAgain
        )
        #expect(try #require(rearmed.request(type: .claudeSessionReset)).deliverAt == reset0900)
    }

    @Test func observedSessionUsageRemainsArmedWithinSameWindow() {
        let reset = now.addingTimeInterval(4 * 60 * 60)
        let active = evaluate(
            current: snapshot(
                .claude,
                weeklyUsed: 20,
                weeklyReset: now.addingTimeInterval(86_400),
                sessionUsed: 10,
                sessionReset: reset
            ),
            preferences: enabledPreferences()
        )
        let laterZero = evaluate(
            current: snapshot(
                .claude,
                weeklyUsed: 20,
                weeklyReset: now.addingTimeInterval(86_400),
                sessionUsed: 0,
                sessionReset: reset,
                fetchedAt: now.addingTimeInterval(300)
            ),
            preferences: enabledPreferences(),
            state: active.state,
            at: now.addingTimeInterval(300)
        )

        #expect(laterZero.request(type: .claudeSessionReset)?.deliverAt == reset)
        #expect(laterZero.state.claudeSessionObservations[accountID]?.observedUsage == true)
    }

    @Test func spontaneousResetFiresBeforeSlackAndResyncsSchedule() throws {
        let oldReset = now.addingTimeInterval(6 * 86_400)
        let newReset = now.addingTimeInterval(7 * 86_400)
        var state = NotificationEngineState()
        state.lastSnapshots[accountID] = snapshot(
            .codex,
            weeklyUsed: 65,
            weeklyReset: oldReset,
            fetchedAt: now.addingTimeInterval(-300)
        )

        let result = evaluate(
            current: snapshot(.codex, weeklyUsed: 0, weeklyReset: newReset),
            preferences: enabledPreferences(),
            state: state
        )

        #expect(try #require(result.request(type: .codexSpontaneousReset)).deliverAt == nil)
        #expect(result.request(type: .codexWeeklyReset)?.deliverAt == newReset)
    }

    @Test func spontaneousResetInsideOnePollSlackIsSuppressed() {
        let expectedReset = now.addingTimeInterval(4 * 60)
        var state = NotificationEngineState()
        state.lastSnapshots[accountID] = snapshot(
            .codex,
            weeklyUsed: 65,
            weeklyReset: expectedReset,
            fetchedAt: now.addingTimeInterval(-300)
        )

        let result = evaluate(
            current: snapshot(
                .codex,
                weeklyUsed: 0,
                weeklyReset: now.addingTimeInterval(7 * 86_400)
            ),
            preferences: enabledPreferences(),
            state: state,
            slack: 5 * 60
        )

        #expect(result.request(type: .codexSpontaneousReset) == nil)
    }

    @Test func spontaneousResetOutsideOnePollSlackFires() {
        let expectedReset = now.addingTimeInterval(6 * 60)
        var state = NotificationEngineState()
        state.lastSnapshots[accountID] = snapshot(
            .codex,
            weeklyUsed: 65,
            weeklyReset: expectedReset,
            fetchedAt: now.addingTimeInterval(-300)
        )

        let result = evaluate(
            current: snapshot(
                .codex,
                weeklyUsed: 0,
                weeklyReset: now.addingTimeInterval(7 * 86_400)
            ),
            preferences: enabledPreferences(),
            state: state,
            slack: 5 * 60
        )

        #expect(result.request(type: .codexSpontaneousReset) != nil)
    }

    @Test func claudeSpontaneousResetUsesWeeklyNotSessionBoundary() {
        var state = NotificationEngineState()
        state.lastSnapshots[accountID] = snapshot(
            .claude,
            weeklyUsed: 50,
            weeklyReset: now.addingTimeInterval(5 * 86_400),
            sessionUsed: 20,
            sessionReset: now.addingTimeInterval(60),
            fetchedAt: now.addingTimeInterval(-300)
        )

        let result = evaluate(
            current: snapshot(
                .claude,
                weeklyUsed: 0,
                weeklyReset: now.addingTimeInterval(7 * 86_400),
                sessionUsed: 0,
                sessionReset: now.addingTimeInterval(5 * 60 * 60)
            ),
            preferences: enabledPreferences(),
            state: state
        )

        #expect(result.request(type: .claudeSpontaneousReset) != nil)
    }

    @Test func bankedResetIncreaseFiresWithNewCount() throws {
        var state = NotificationEngineState()
        state.lastSnapshots[accountID] = snapshot(
            .codex,
            weeklyUsed: 40,
            weeklyReset: now.addingTimeInterval(86_400),
            banked: 1,
            fetchedAt: now.addingTimeInterval(-300)
        )
        let result = evaluate(
            current: snapshot(
                .codex,
                weeklyUsed: 41,
                weeklyReset: now.addingTimeInterval(86_400),
                banked: 2
            ),
            preferences: enabledPreferences(),
            state: state
        )

        let request = try #require(result.request(type: .codexBankedReset))
        #expect(request.body == "You now have 2 banked resets available.")
        #expect(request.deliverAt == nil)
    }

    @Test func bankedResetUnchangedOrDecreasedDoesNotFire() {
        for newCount in [2, 1] {
            var state = NotificationEngineState()
            state.lastSnapshots[accountID] = snapshot(
                .codex,
                weeklyUsed: 40,
                weeklyReset: now.addingTimeInterval(86_400),
                banked: 2,
                fetchedAt: now.addingTimeInterval(-300)
            )
            let result = evaluate(
                current: snapshot(
                    .codex,
                    weeklyUsed: 41,
                    weeklyReset: now.addingTimeInterval(86_400),
                    banked: newCount
                ),
                preferences: enabledPreferences(),
                state: state
            )
            #expect(result.request(type: .codexBankedReset) == nil)
        }
    }

    @Test func persistedStateDedupesSameEventAcrossRelaunch() throws {
        var state = NotificationEngineState()
        state.lastSnapshots[accountID] = snapshot(
            .codex,
            weeklyUsed: 50,
            weeklyReset: now.addingTimeInterval(6 * 86_400),
            banked: 0,
            fetchedAt: now.addingTimeInterval(-300)
        )
        let current = snapshot(
            .codex,
            weeklyUsed: 0,
            weeklyReset: now.addingTimeInterval(7 * 86_400),
            banked: 1
        )
        let first = evaluate(
            current: current,
            preferences: enabledPreferences(),
            state: state
        )
        #expect(first.request(type: .codexSpontaneousReset) != nil)
        #expect(first.request(type: .codexBankedReset) != nil)

        let persisted = try JSONEncoder().encode(first.state)
        let restored = try JSONDecoder().decode(NotificationEngineState.self, from: persisted)
        let afterRelaunch = evaluate(
            current: current,
            preferences: enabledPreferences(),
            state: restored
        )

        #expect(afterRelaunch.request(type: .codexSpontaneousReset) == nil)
        #expect(afterRelaunch.request(type: .codexBankedReset) == nil)
    }

    private func evaluate(
        current: UsageSnapshot,
        preferences: NotificationPreferences,
        state: NotificationEngineState = NotificationEngineState(),
        at date: Date? = nil,
        slack: TimeInterval = UsageNotificationEngine.defaultSpontaneousResetSlack
    ) -> NotificationEngineResult {
        UsageNotificationEngine.evaluate(
            polls: [NotificationPollSnapshot(accountID: accountID, snapshot: current)],
            preferences: preferences,
            state: state,
            now: date ?? now,
            spontaneousResetSlack: slack
        )
    }

    private func enabledPreferences() -> NotificationPreferences {
        var preferences = NotificationPreferences.default
        preferences.masterEnabled = true
        return preferences
    }

    private func snapshot(
        _ provider: ProviderID,
        weeklyUsed: Double,
        weeklyReset: Date,
        sessionUsed: Double? = nil,
        sessionReset: Date? = nil,
        banked: Int? = nil,
        fetchedAt: Date? = nil
    ) -> UsageSnapshot {
        var windows = [LimitWindow(
            kind: provider == .cursor ? .monthly : .weekly,
            label: provider == .cursor ? "Monthly" : "Weekly",
            usedPercent: weeklyUsed,
            resetsAt: weeklyReset
        )]
        if let sessionUsed {
            windows.insert(LimitWindow(
                kind: .session,
                label: "Session",
                usedPercent: sessionUsed,
                resetsAt: sessionReset
            ), at: 0)
        }
        return UsageSnapshot(
            provider: provider,
            plan: nil,
            windows: windows,
            resetCreditsAvailable: banked,
            fetchedAt: fetchedAt ?? now
        )
    }
}

private extension NotificationEngineResult {
    func request(type: UsageNotificationType) -> UsageNotificationRequest? {
        commands.compactMap { command in
            guard case .deliver(let request) = command,
                  request.type == type else { return nil }
            return request
        }.first
    }
}
