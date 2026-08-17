import Foundation
import UsageKit

/// Reviewable, offline sample mode. Marker and fixtures contain no credentials;
/// real account files remain untouched and reappear when demo mode exits.
enum DemoModeStore {
    private static var markerURL: URL {
        AppGroup.containerURL.appendingPathComponent("demo-mode-enabled")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: markerURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try Data().write(to: markerURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: markerURL.path) {
            try FileManager.default.removeItem(at: markerURL)
        }
    }
}

enum DemoData {
    private static let accountIDs: [(ProviderID, UUID, String)] = [
        (.codex, UUID(uuidString: "D0000000-0000-0000-0000-000000000001")!, "Codex sample"),
        (.claude, UUID(uuidString: "D0000000-0000-0000-0000-000000000002")!, "Claude sample"),
        (.cursor, UUID(uuidString: "D0000000-0000-0000-0000-000000000003")!, "Cursor sample"),
        (.openRouter, UUID(uuidString: "D0000000-0000-0000-0000-000000000004")!, "OpenRouter sample"),
    ]

    static func states(now: Date = Date()) -> [AccountState] {
        accountIDs.enumerated().map { index, item in
            let (provider, id, label) = item
            let windows: [LimitWindow]
            switch provider {
            case .claude:
                windows = [
                    LimitWindow(kind: .session, label: "Session", usedPercent: 67,
                                resetsAt: now.addingTimeInterval(3.7 * 60 * 60)),
                    LimitWindow(kind: .weekly, label: "Weekly", usedPercent: 54,
                                resetsAt: now.addingTimeInterval(3.4 * 24 * 60 * 60)),
                ]
            case .codex:
                windows = [
                    LimitWindow(kind: .session, label: "Session", usedPercent: 42,
                                resetsAt: now.addingTimeInterval(2.2 * 60 * 60)),
                    LimitWindow(kind: .weekly, label: "Weekly", usedPercent: 71,
                                resetsAt: now.addingTimeInterval(5.6 * 24 * 60 * 60)),
                ]
            case .cursor:
                windows = [
                    LimitWindow(kind: .monthly, label: "Composer", usedPercent: 42,
                                resetsAt: now.addingTimeInterval(12 * 24 * 60 * 60)),
                    LimitWindow(kind: .monthly, label: "API", usedPercent: 18,
                                resetsAt: now.addingTimeInterval(12 * 24 * 60 * 60)),
                ]
            case .openRouter, .antigravity:
                windows = []
            }
            let onDemand: [OnDemandUsage]
            if provider == .openRouter {
                onDemand = [
                    OnDemandUsage(id: "demo-openrouter-key-spending",
                                  label: "API key spending",
                                  kind: .spendingLimit,
                                  scope: .personal,
                                  isEnabled: true,
                                  isUnlimited: true,
                                  used: 23.75),
                ]
            } else {
                onDemand = [
                    OnDemandUsage(id: "demo-\(provider.rawValue)-personal",
                                  label: "Personal limit",
                                  kind: .personalAllocation,
                                  scope: .personal,
                                  isEnabled: true,
                                  used: Double(18 + index * 9),
                                  limit: 100,
                                  remaining: Double(82 - index * 9),
                                  resetsAt: now.addingTimeInterval(12 * 24 * 60 * 60)),
                ]
            }
            let snapshot = UsageSnapshot(provider: provider,
                                         plan: provider == .cursor ? "pro" : nil,
                                         windows: windows,
                                         onDemand: onDemand,
                                         // Only OpenRouter reports a tier at all.
                                         isFreeTier: provider == .openRouter ? true : nil,
                                         fetchedAt: now)
            return AccountState(account: StoredAccount(id: id,
                                                       provider: provider,
                                                       label: label),
                                snapshot: snapshot,
                                lastError: nil,
                                lastFailure: nil,
                                updatedAt: now)
        }
    }

    static func historySamples(now: Date = Date()) -> [UsageHistorySample] {
        states(now: now).enumerated().flatMap { index, state -> [UsageHistorySample] in
            guard let snapshot = state.snapshot else { return [] }
            return (-83...0).map { dayOffset in
                let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: now) ?? now
                let day = dayOffset + 83
                let windows = snapshot.windows.map { window in
                    LimitWindow(kind: window.kind,
                                label: window.label,
                                usedPercent: min(96, Double((day * 9 + index * 13) % 64)),
                                resetsAt: window.resetsAt)
                }
                return UsageHistorySample(accountID: state.id,
                                          snapshot: UsageSnapshot(provider: snapshot.provider,
                                                                  plan: snapshot.plan,
                                                                  windows: windows,
                                                                  onDemand: snapshot.onDemand,
                                                                  fetchedAt: date))
            }
        }
    }
}
