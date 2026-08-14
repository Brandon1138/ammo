import Foundation

public enum UsageNotificationType: String, CaseIterable, Codable, Sendable {
    case codexWeeklyReset
    case codexSpontaneousReset
    case codexBankedReset
    case claudeSessionReset
    case claudeWeeklyReset
    case claudeSpontaneousReset
    case cursorMonthlyReset

    public var identifierPrefix: String {
        "ammo.notification.\(rawValue)."
    }
}

public struct UsageNotificationRequest: Equatable, Sendable {
    public let identifier: String
    public let type: UsageNotificationType
    public let title: String
    public let body: String
    public let deliverAt: Date?

    public init(
        identifier: String,
        type: UsageNotificationType,
        title: String,
        body: String,
        deliverAt: Date?
    ) {
        self.identifier = identifier
        self.type = type
        self.title = title
        self.body = body
        self.deliverAt = deliverAt
    }
}

public enum UsageNotificationCommand: Equatable, Sendable {
    case deliver(UsageNotificationRequest)
    case cancelIdentifier(String)
    case cancelType(UsageNotificationType)
}

public struct NotificationPollSnapshot: Equatable, Sendable {
    public let accountID: String
    public let snapshot: UsageSnapshot

    public init(accountID: String, snapshot: UsageSnapshot) {
        self.accountID = accountID
        self.snapshot = snapshot
    }
}

public struct ClaudeSessionObservation: Codable, Equatable, Sendable {
    public var resetAt: Date?
    public var observedUsage: Bool

    public init(resetAt: Date? = nil, observedUsage: Bool = false) {
        self.resetAt = resetAt
        self.observedUsage = observedUsage
    }
}

public struct NotificationEngineState: Codable, Equatable, Sendable {
    public var lastSnapshots: [String: UsageSnapshot]
    public var claudeSessionObservations: [String: ClaudeSessionObservation]
    public var lastFiredMarkers: [String: String]

    public init(
        lastSnapshots: [String: UsageSnapshot] = [:],
        claudeSessionObservations: [String: ClaudeSessionObservation] = [:],
        lastFiredMarkers: [String: String] = [:]
    ) {
        self.lastSnapshots = lastSnapshots
        self.claudeSessionObservations = claudeSessionObservations
        self.lastFiredMarkers = lastFiredMarkers
    }
}

public struct NotificationEngineResult: Equatable, Sendable {
    public let state: NotificationEngineState
    public let commands: [UsageNotificationCommand]

    public init(state: NotificationEngineState, commands: [UsageNotificationCommand]) {
        self.state = state
        self.commands = commands
    }
}

/// Pure notification decision engine. Callers persist returned state before
/// executing commands so relaunches cannot fire one logical event twice.
public enum UsageNotificationEngine {
    public static let defaultSpontaneousResetSlack: TimeInterval = 5 * 60

    public static func evaluate(
        polls: [NotificationPollSnapshot],
        preferences: NotificationPreferences,
        state initialState: NotificationEngineState,
        now: Date,
        spontaneousResetSlack: TimeInterval = defaultSpontaneousResetSlack
    ) -> NotificationEngineResult {
        var state = initialState
        var commands = cancellationCommands(preferences: preferences)

        for poll in polls {
            let previous = state.lastSnapshots[poll.accountID]
            let current = poll.snapshot

            // A slower overlapping fetch must not roll persisted baselines or
            // schedules backward after a newer result already committed.
            if let previous, current.fetchedAt < previous.fetchedAt { continue }

            if current.provider == .claude {
                updateClaudeSessionObservation(
                    accountID: poll.accountID,
                    snapshot: current,
                    state: &state
                )
            }

            guard preferences.masterEnabled else {
                state.lastSnapshots[poll.accountID] = current
                continue
            }

            planDeterministicNotifications(
                accountID: poll.accountID,
                snapshot: current,
                preferences: preferences,
                state: state,
                now: now,
                commands: &commands
            )

            if let previous {
                planSpontaneousReset(
                    accountID: poll.accountID,
                    previous: previous,
                    current: current,
                    preferences: preferences,
                    state: &state,
                    now: now,
                    slack: spontaneousResetSlack,
                    commands: &commands
                )
                planBankedReset(
                    accountID: poll.accountID,
                    previous: previous,
                    current: current,
                    preferences: preferences,
                    state: &state,
                    commands: &commands
                )
            }

            state.lastSnapshots[poll.accountID] = current
        }

        return NotificationEngineResult(state: state, commands: commands)
    }

    private static func cancellationCommands(
        preferences: NotificationPreferences
    ) -> [UsageNotificationCommand] {
        UsageNotificationType.allCases.compactMap { type in
            preferences.masterEnabled && preferences.isEnabled(type) ? nil : .cancelType(type)
        }
    }

    private static func planDeterministicNotifications(
        accountID: String,
        snapshot: UsageSnapshot,
        preferences: NotificationPreferences,
        state: NotificationEngineState,
        now: Date,
        commands: inout [UsageNotificationCommand]
    ) {
        switch snapshot.provider {
        case .codex where preferences.codexWeeklyReset:
            planReset(
                type: .codexWeeklyReset,
                accountID: accountID,
                resetAt: resetDate(kind: .weekly, in: snapshot),
                title: "Codex weekly usage reset",
                body: "Your Codex weekly usage is available again.",
                now: now,
                commands: &commands
            )
        case .claude:
            if preferences.claudeWeeklyReset {
                planReset(
                    type: .claudeWeeklyReset,
                    accountID: accountID,
                    resetAt: resetDate(kind: .weekly, in: snapshot),
                    title: "Claude weekly usage reset",
                    body: "Your Claude weekly usage is available again.",
                    now: now,
                    commands: &commands
                )
            }
            if preferences.claudeSessionReset {
                let observation = state.claudeSessionObservations[accountID]
                planReset(
                    type: .claudeSessionReset,
                    accountID: accountID,
                    resetAt: observation?.observedUsage == true ? observation?.resetAt : nil,
                    title: "Claude session usage reset",
                    body: "Your Claude session usage is available again.",
                    now: now,
                    commands: &commands
                )
            }
        case .cursor where preferences.cursorMonthlyReset:
            planReset(
                type: .cursorMonthlyReset,
                accountID: accountID,
                resetAt: resetDate(kind: .monthly, in: snapshot),
                title: "Cursor monthly usage reset",
                body: "Your Cursor monthly usage is available again.",
                now: now,
                commands: &commands
            )
        default:
            break
        }
    }

    private static func planReset(
        type: UsageNotificationType,
        accountID: String,
        resetAt: Date?,
        title: String,
        body: String,
        now: Date,
        commands: inout [UsageNotificationCommand]
    ) {
        let identifier = stableIdentifier(type: type, accountID: accountID)
        guard let resetAt, resetAt > now else {
            commands.append(.cancelIdentifier(identifier))
            return
        }
        commands.append(.deliver(UsageNotificationRequest(
            identifier: identifier,
            type: type,
            title: title,
            body: body,
            deliverAt: resetAt
        )))
    }

    private static func updateClaudeSessionObservation(
        accountID: String,
        snapshot: UsageSnapshot,
        state: inout NotificationEngineState
    ) {
        guard let session = snapshot.windows.first(where: { $0.kind == .session }),
              let resetAt = session.resetsAt else {
            state.claudeSessionObservations[accountID] = ClaudeSessionObservation()
            return
        }

        let previous = state.claudeSessionObservations[accountID]
        let sameWindow = previous?.resetAt == resetAt
        state.claudeSessionObservations[accountID] = ClaudeSessionObservation(
            resetAt: resetAt,
            observedUsage: session.usedPercent > 0.000_001
                || (sameWindow && previous?.observedUsage == true)
        )
    }

    private static func planSpontaneousReset(
        accountID: String,
        previous: UsageSnapshot,
        current: UsageSnapshot,
        preferences: NotificationPreferences,
        state: inout NotificationEngineState,
        now: Date,
        slack: TimeInterval,
        commands: inout [UsageNotificationCommand]
    ) {
        guard previous.provider == current.provider else { return }
        let type: UsageNotificationType
        let providerName: String
        switch current.provider {
        case .codex where preferences.codexSpontaneousReset:
            type = .codexSpontaneousReset
            providerName = "Codex"
        case .claude where preferences.claudeSpontaneousReset:
            type = .claudeSpontaneousReset
            providerName = "Claude"
        default:
            return
        }

        let previousWindows = quotaWindows(in: previous)
        let currentWindows = quotaWindows(in: current)
        guard !previousWindows.isEmpty,
              !currentWindows.isEmpty,
              previousWindows.contains(where: { $0.usedPercent > 0.000_001 }),
              currentWindows.allSatisfy({ $0.usedPercent <= 0.000_001 }),
              let expectedReset = expectedFullResetDate(in: previous),
              now.addingTimeInterval(max(0, slack)) < expectedReset else {
            return
        }

        let marker = "reset:\(milliseconds(current.fetchedAt))"
        let markerKey = firedMarkerKey(type: type, accountID: accountID)
        guard state.lastFiredMarkers[markerKey] != marker else { return }
        state.lastFiredMarkers[markerKey] = marker

        commands.append(.deliver(UsageNotificationRequest(
            identifier: "\(type.identifierPrefix)\(accountID).\(marker)",
            type: type,
            title: "\(providerName) usage reset early",
            body: "Your \(providerName) usage limits reset before the expected time.",
            deliverAt: nil
        )))
    }

    private static func planBankedReset(
        accountID: String,
        previous: UsageSnapshot,
        current: UsageSnapshot,
        preferences: NotificationPreferences,
        state: inout NotificationEngineState,
        commands: inout [UsageNotificationCommand]
    ) {
        guard previous.provider == current.provider,
              current.provider == .codex,
              preferences.codexBankedReset,
              let oldCount = previous.resetCreditsAvailable,
              let newCount = current.resetCreditsAvailable,
              newCount > oldCount else {
            return
        }

        let marker = "count:\(newCount):\(milliseconds(current.fetchedAt))"
        let markerKey = firedMarkerKey(type: .codexBankedReset, accountID: accountID)
        guard state.lastFiredMarkers[markerKey] != marker else { return }
        state.lastFiredMarkers[markerKey] = marker

        let noun = newCount == 1 ? "reset" : "resets"
        commands.append(.deliver(UsageNotificationRequest(
            identifier: "\(UsageNotificationType.codexBankedReset.identifierPrefix)\(accountID).\(marker)",
            type: .codexBankedReset,
            title: "Codex banked reset granted",
            body: "You now have \(newCount) banked \(noun) available.",
            deliverAt: nil
        )))
    }

    private static func quotaWindows(in snapshot: UsageSnapshot) -> [LimitWindow] {
        snapshot.windows.filter {
            $0.kind == .session || $0.kind == .weekly || $0.kind == .monthly
                || $0.kind == .modelScoped
        }
    }

    /// Full Claude resets are anchored to weekly allowance, not rolling 5-hour
    /// session boundary. Codex and fallback providers use longest known window.
    private static func expectedFullResetDate(in snapshot: UsageSnapshot) -> Date? {
        if let weekly = resetDate(kind: .weekly, in: snapshot) { return weekly }
        return quotaWindows(in: snapshot).compactMap(\.resetsAt).max()
    }

    private static func resetDate(kind: WindowKind, in snapshot: UsageSnapshot) -> Date? {
        snapshot.windows
            .filter { $0.kind == kind }
            .compactMap(\.resetsAt)
            .min()
    }

    private static func stableIdentifier(
        type: UsageNotificationType,
        accountID: String
    ) -> String {
        "\(type.identifierPrefix)\(accountID)"
    }

    private static func firedMarkerKey(
        type: UsageNotificationType,
        accountID: String
    ) -> String {
        "\(type.rawValue):\(accountID)"
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
}

private extension NotificationPreferences {
    func isEnabled(_ type: UsageNotificationType) -> Bool {
        switch type {
        case .codexWeeklyReset: codexWeeklyReset
        case .codexSpontaneousReset: codexSpontaneousReset
        case .codexBankedReset: codexBankedReset
        case .claudeSessionReset: claudeSessionReset
        case .claudeWeeklyReset: claudeWeeklyReset
        case .claudeSpontaneousReset: claudeSpontaneousReset
        case .cursorMonthlyReset: cursorMonthlyReset
        }
    }
}
