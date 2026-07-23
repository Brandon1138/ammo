import Foundation
import UsageKit

/// Persistent per-account fetch state shared by the app and widget processes.
/// Claiming happens under a file lock before network work begins.
enum RefreshLedgerStore {
    static let minimumFetchInterval: TimeInterval = 60
    private static let inFlightLease: TimeInterval = 2 * 60

    struct Claim: Sendable {
        let isGranted: Bool
        let nextEligibleAt: Date
    }

    private struct Ledger: Codable {
        var accounts: [String: Record] = [:]
    }

    private struct Record: Codable {
        var lastAttemptAt: Date?
        var lastSuccessAt: Date?
        var nextEligibleAt: Date?
        var nextScheduledAt: Date?
        var inFlightUntil: Date?
        var consecutiveFailures = 0
        var consecutiveUnchangedRefreshes: Int?
        var lastReason: String?
    }

    private static var fileURL: URL {
        AppGroup.containerURL.appendingPathComponent("refresh-ledger.json")
    }

    private static var lock: SharedFileLock {
        SharedFileLock(url: AppGroup.containerURL.appendingPathComponent("refresh-ledger.lock"))
    }

    static func claim(accountID: UUID, reason: RefreshReason, now: Date = Date()) -> Claim {
        do {
            return try lock.withLock {
                var ledger = load()
                var record = ledger.accounts[accountID.uuidString] ?? Record()
                let hardEligibleAt = max(
                    max(record.lastAttemptAt?.addingTimeInterval(minimumFetchInterval) ?? .distantPast,
                        record.nextEligibleAt ?? .distantPast),
                    record.inFlightUntil ?? .distantPast)
                let eligibleAt = reason.usesAdaptiveSchedule
                    ? max(hardEligibleAt, record.nextScheduledAt ?? .distantPast)
                    : hardEligibleAt
                guard eligibleAt <= now else {
                    return Claim(isGranted: false, nextEligibleAt: eligibleAt)
                }

                record.lastAttemptAt = now
                record.nextEligibleAt = now.addingTimeInterval(minimumFetchInterval)
                record.inFlightUntil = now.addingTimeInterval(inFlightLease)
                record.lastReason = reason.rawValue
                ledger.accounts[accountID.uuidString] = record
                try save(ledger)
                return Claim(isGranted: true,
                             nextEligibleAt: now.addingTimeInterval(minimumFetchInterval))
            }
        } catch {
            AmmoLog.refresh.error("Unable to claim refresh lease: \(String(describing: error), privacy: .private)")
            return Claim(isGranted: false, nextEligibleAt: now.addingTimeInterval(5))
        }
    }

    /// The next time a refresh for this reason may contact the provider.
    /// Returns nil when the account is eligible now.
    static func nextEligibleAt(
        accountID: UUID,
        reason: RefreshReason,
        now: Date = Date()
    ) -> Date? {
        do {
            return try lock.withLock {
                let record = load().accounts[accountID.uuidString]
                let hardEligibleAt = max(
                    max(record?.lastAttemptAt?.addingTimeInterval(minimumFetchInterval) ?? .distantPast,
                        record?.nextEligibleAt ?? .distantPast),
                    record?.inFlightUntil ?? .distantPast)
                let eligibleAt = reason.usesAdaptiveSchedule
                    ? max(hardEligibleAt, record?.nextScheduledAt ?? .distantPast)
                    : hardEligibleAt
                return eligibleAt > now ? eligibleAt : nil
            }
        } catch {
            AmmoLog.refresh.error("Unable to read refresh eligibility: \(String(describing: error), privacy: .private)")
            return now.addingTimeInterval(5)
        }
    }

    static func finishSuccess(
        accountID: UUID,
        snapshot: UsageSnapshot,
        previousSnapshot: UsageSnapshot?,
        at date: Date = Date()
    ) {
        update(accountID: accountID) { record in
            let unchangedCount = UsageRefreshSchedule.nextUnchangedRefreshCount(
                previousCount: record.consecutiveUnchangedRefreshes ?? 0,
                previousSnapshot: previousSnapshot,
                currentSnapshot: snapshot)

            record.lastSuccessAt = date
            record.inFlightUntil = nil
            record.consecutiveFailures = 0
            record.consecutiveUnchangedRefreshes = unchangedCount
            record.nextEligibleAt = max(record.nextEligibleAt ?? .distantPast,
                                        date.addingTimeInterval(minimumFetchInterval))
            record.nextScheduledAt = UsageRefreshSchedule.nextRefreshDate(
                snapshots: [snapshot],
                consecutiveUnchangedRefreshes: unchangedCount,
                now: date)
        }
    }

    /// The earliest passive refresh due across the supplied accounts. WidgetKit
    /// and BGTaskScheduler both use this so their wake requests agree with the
    /// same persistent activity state used by the network gate.
    static func nextRefreshDate(states: [AccountState], now: Date = Date()) -> Date {
        guard !states.isEmpty else {
            return UsageRefreshSchedule.nextRefreshDate(snapshots: [], now: now)
        }

        do {
            return try lock.withLock {
                let ledger = load()
                return states.map { state in
                    let record = ledger.accounts[state.account.id.uuidString]
                    let unchangedCount = record?.consecutiveUnchangedRefreshes ?? 2
                    let fallback = UsageRefreshSchedule.nextRefreshDate(
                        snapshots: state.snapshot.map { [$0] } ?? [],
                        consecutiveUnchangedRefreshes: unchangedCount,
                        now: now)
                    let scheduled = record?.nextScheduledAt ?? fallback
                    let backedOff = record?.nextEligibleAt ?? .distantPast
                    let inFlight = record?.inFlightUntil ?? .distantPast
                    return max(max(scheduled, backedOff), inFlight)
                }.min() ?? now.addingTimeInterval(UsageRefreshSchedule.quietInterval)
            }
        } catch {
            AmmoLog.refresh.error("Unable to read adaptive refresh schedule: \(String(describing: error), privacy: .private)")
            return UsageRefreshSchedule.nextRefreshDate(
                snapshots: states.compactMap(\.snapshot), now: now)
        }
    }

    static func finishFailure(accountID: UUID, status: Int?, at date: Date = Date()) {
        update(accountID: accountID) { record in
            record.inFlightUntil = nil
            record.consecutiveFailures += 1
            let backoff = RefreshFailureBackoff.delay(
                consecutiveFailures: record.consecutiveFailures,
                status: status)
            record.nextEligibleAt = date.addingTimeInterval(backoff)
        }
    }

    static func remove(accountID: UUID) {
        do {
            try lock.withLock {
                var ledger = load()
                ledger.accounts.removeValue(forKey: accountID.uuidString)
                try save(ledger)
            }
        } catch {
            AmmoLog.refresh.error("Unable to remove refresh ledger entry: \(String(describing: error), privacy: .private)")
        }
    }

    private static func update(accountID: UUID, mutate: (inout Record) -> Void) {
        do {
            try lock.withLock {
                var ledger = load()
                var record = ledger.accounts[accountID.uuidString] ?? Record()
                mutate(&record)
                ledger.accounts[accountID.uuidString] = record
                try save(ledger)
            }
        } catch {
            AmmoLog.refresh.error("Unable to update refresh ledger: \(String(describing: error), privacy: .private)")
        }
    }

    private static func load() -> Ledger {
        guard let data = try? Data(contentsOf: fileURL) else { return Ledger() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Ledger.self, from: data)) ?? Ledger()
    }

    private static func save(_ ledger: Ledger) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(ledger).write(to: fileURL, options: .atomic)
    }
}
