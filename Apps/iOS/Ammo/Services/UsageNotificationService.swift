import Foundation
import UsageKit
import UserNotifications

/// App-only bridge from successful usage polls to UsageKit's pure planner.
/// Settings owns authorization requests; this service only reads status.
actor UsageNotificationService {
    static let shared = UsageNotificationService()

    static let stateStorageKey = "ammo.notificationEngineState"

    private let defaults: UserDefaults
    private let center: any LocalNotificationCenter

    init(
        defaults: UserDefaults = .standard,
        center: any LocalNotificationCenter = SystemLocalNotificationCenter()
    ) {
        self.defaults = defaults
        self.center = center
    }

    func process(
        snapshots: [UUID: UsageSnapshot],
        refreshedAccountIDs: Set<UUID>,
        now: Date = Date()
    ) async {
        guard await center.isAuthorized() else { return }

        // Re-read every pass because Settings writes this value independently.
        let preferences = loadPreferences()
        let polls = snapshots.compactMap { accountID, snapshot -> NotificationPollSnapshot? in
            guard refreshedAccountIDs.contains(accountID) else { return nil }
            return NotificationPollSnapshot(
                accountID: accountID.uuidString.lowercased(),
                snapshot: snapshot
            )
        }

        let result = UsageNotificationEngine.evaluate(
            polls: polls,
            preferences: preferences,
            state: loadState(),
            now: now
        )

        // Persist dedupe markers before delivery. Crash/relaunch can lose one
        // immediate alert, but cannot deliver the same logical event twice.
        saveState(result.state)
        await execute(result.commands)
    }

    private func loadPreferences() -> NotificationPreferences {
        guard let data = defaults.data(forKey: NotificationPreferences.storageKey),
              let preferences = try? JSONDecoder().decode(
                NotificationPreferences.self,
                from: data
              ) else {
            return .default
        }
        return preferences
    }

    private func loadState() -> NotificationEngineState {
        guard let data = defaults.data(forKey: Self.stateStorageKey),
              let state = try? JSONDecoder().decode(
                NotificationEngineState.self,
                from: data
              ) else {
            return NotificationEngineState()
        }
        return state
    }

    private func saveState(_ state: NotificationEngineState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.stateStorageKey)
    }

    private func execute(_ commands: [UsageNotificationCommand]) async {
        for command in commands {
            switch command {
            case .deliver(let request):
                do {
                    try await center.deliver(request)
                } catch {
                    AmmoLog.refresh.error("Unable to schedule usage notification: \(String(describing: error), privacy: .private)")
                }
            case .cancelIdentifier(let identifier):
                await center.cancelPending(identifier: identifier)
            case .cancelType(let type):
                await center.cancelPending(identifierPrefix: type.identifierPrefix)
            }
        }
    }
}

final class SystemLocalNotificationCenter: LocalNotificationCenter, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    func deliver(_ request: UsageNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = ["usageNotificationType": request.type.rawValue]

        let trigger: UNNotificationTrigger?
        if let deliverAt = request.deliverAt {
            trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, deliverAt.timeIntervalSinceNow),
                repeats: false
            )
        } else {
            trigger = nil
        }

        try await center.add(UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: trigger
        ))
    }

    func cancelPending(identifier: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelPending(identifierPrefix: String) async {
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
