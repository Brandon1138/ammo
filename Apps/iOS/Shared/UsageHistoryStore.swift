import Foundation
import UsageKit

/// Local-only, reset-aware history shared by the app and widget extension.
/// Samples are downsampled to at most one per 15-minute interval unless a
/// provider cycle changes, then retained for 90 days.
enum UsageHistoryStore {
    private static let retention: TimeInterval = 90 * 24 * 60 * 60
    private static let minimumSampleInterval: TimeInterval = 15 * 60

    static var fileURL: URL {
        AppGroup.containerURL.appendingPathComponent("usage-history.json")
    }

    private static var lock: SharedFileLock {
        SharedFileLock(url: AppGroup.containerURL.appendingPathComponent("usage-history.lock"))
    }

    static func load() -> [UsageHistorySample] {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([UsageHistorySample].self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        } catch {
            AmmoLog.sharedStore.error("Unable to load usage history: \(String(describing: error), privacy: .private)")
            return []
        }
    }

    static func record(snapshot: UsageSnapshot, for accountID: UUID) throws {
        try lock.withLock {
            var samples = loadUnlocked()
            let cutoff = snapshot.fetchedAt.addingTimeInterval(-retention)
            samples.removeAll { $0.snapshot.fetchedAt < cutoff }

            let newSample = UsageHistorySample(accountID: accountID, snapshot: snapshot)
            if let lastIndex = samples.lastIndex(where: { $0.accountID == accountID }) {
                let previous = samples[lastIndex]
                guard snapshot.fetchedAt >= previous.snapshot.fetchedAt else { return }

                if snapshot.fetchedAt.timeIntervalSince(previous.snapshot.fetchedAt) < minimumSampleInterval,
                   !cycleChanged(from: previous.snapshot, to: snapshot) {
                    samples[lastIndex] = newSample
                } else if snapshot.fetchedAt == previous.snapshot.fetchedAt {
                    samples[lastIndex] = newSample
                } else {
                    samples.append(newSample)
                }
            } else {
                samples.append(newSample)
            }

            try saveUnlocked(samples.sorted { $0.snapshot.fetchedAt < $1.snapshot.fetchedAt })
        }
    }

    static func remove(accountID: UUID) throws {
        try lock.withLock {
            var samples = loadUnlocked()
            samples.removeAll { $0.accountID == accountID }
            try saveUnlocked(samples)
        }
    }

    private static func cycleChanged(from previous: UsageSnapshot, to current: UsageSnapshot) -> Bool {
        for window in current.windows {
            guard let oldWindow = previous.windows.first(where: { $0.id == window.id }) else {
                return true
            }
            if let oldReset = oldWindow.resetsAt, let newReset = window.resetsAt,
               newReset.timeIntervalSince(oldReset) > 60 {
                return true
            }
            if window.usedPercent + 0.05 < oldWindow.usedPercent {
                return true
            }
        }
        return previous.windows.count != current.windows.count
    }

    private static func loadUnlocked() -> [UsageHistorySample] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([UsageHistorySample].self, from: data)) ?? []
    }

    private static func saveUnlocked(_ samples: [UsageHistorySample]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(samples).write(to: fileURL, options: .atomic)
    }
}
