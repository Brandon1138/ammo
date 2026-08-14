import Foundation
import UsageKit
import UserNotifications

/// App-only bridge from successful usage polls to UsageKit's pure planner.
/// Settings owns authorization requests; this service only reads status.
actor UsageNotificationService {
    static let shared = UsageNotificationService()

    private let processor: UsageNotificationProcessor

    init(
        storage: NotificationPreferencesStorage = NotificationPreferencesStorage(
            suiteName: AppGroup.id
        ),
        center: any LocalNotificationCenter = SystemLocalNotificationCenter()
    ) {
        processor = UsageNotificationProcessor(
            storage: storage,
            center: center,
            deliveryErrorHandler: { message in
                AmmoLog.refresh.error("\(message, privacy: .private)")
            }
        )
    }

    func process(
        snapshots: [UUID: UsageSnapshot],
        refreshedAccountIDs: Set<UUID>,
        knownAccountIDs: Set<UUID>,
        now: Date = Date()
    ) async {
        let polls = snapshots.compactMap { accountID, snapshot -> NotificationPollSnapshot? in
            guard refreshedAccountIDs.contains(accountID) else { return nil }
            return NotificationPollSnapshot(
                accountID: accountID.uuidString.lowercased(),
                snapshot: snapshot
            )
        }

        await processor.process(
            polls: polls,
            knownAccountIDs: Set(knownAccountIDs.map { $0.uuidString.lowercased() }),
            now: now
        )
    }

    func preferencesDidChange(now: Date = Date()) async {
        await processor.preferencesDidChange(now: now)
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

    func cancelPending(accountID: String) async {
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { identifier in
                UsageNotificationType.allCases.contains { type in
                    let stableIdentifier = "\(type.identifierPrefix)\(accountID)"
                    return identifier == stableIdentifier
                        || identifier.hasPrefix("\(stableIdentifier).")
                }
            }
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
