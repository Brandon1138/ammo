import Foundation

/// One provider snapshot accepted for an account and retained for local history.
public struct UsageHistorySample: Codable, Equatable, Identifiable, Sendable {
    public let accountID: UUID
    public let snapshot: UsageSnapshot

    public var id: String {
        "\(accountID.uuidString):\(snapshot.fetchedAt.timeIntervalSince1970)"
    }

    public init(accountID: UUID, snapshot: UsageSnapshot) {
        self.accountID = accountID
        self.snapshot = snapshot
    }
}

/// One calendar cell in the contribution-style activity heatmap.
public struct UsageActivityDay: Equatable, Identifiable, Sendable {
    public let date: Date
    public let observedUsedPercent: Double
    public let isFuture: Bool

    public var id: Date { date }
    public var isActive: Bool { observedUsedPercent >= 0.05 }

    /// Four stable activity bands plus the inactive state. Bands never
    /// auto-rescale, so the same shade keeps the same meaning over time.
    public var intensityLevel: Int {
        switch observedUsedPercent {
        case ..<0.05: 0
        case ..<2: 1
        case ..<5: 2
        case ..<10: 3
        default: 4
        }
    }

    public init(date: Date, observedUsedPercent: Double, isFuture: Bool) {
        self.date = date
        self.observedUsedPercent = observedUsedPercent
        self.isFuture = isFuture
    }
}

public struct UsageTrendPoint: Equatable, Identifiable, Sendable {
    public let date: Date
    public let remainingPercent: Double
    public let resetOccurred: Bool

    public var id: Date { date }

    public init(date: Date, remainingPercent: Double, resetOccurred: Bool) {
        self.date = date
        self.remainingPercent = remainingPercent
        self.resetOccurred = resetOccurred
    }
}

public enum UsageHistoryAnalysis {
    /// Builds a week-aligned, column-major heatmap. Usage is assigned to the
    /// day Ammo first observed it, since providers do not expose event times.
    public static func activityDays(
        samples: [UsageHistorySample],
        accountID: UUID,
        windowID: String,
        endingAt endDate: Date,
        weekCount: Int,
        calendar: Calendar = .current
    ) -> [UsageActivityDay] {
        let weeks = max(1, weekCount)
        let today = calendar.startOfDay(for: endDate)
        // GitHub contribution graphs always use Sunday through Saturday rows,
        // regardless of the device locale's preferred first weekday.
        let weekday = calendar.component(.weekday, from: today)
        let currentWeekStart = calendar.date(byAdding: .day,
                                             value: -(weekday - 1),
                                             to: today) ?? today
        let gridStart = calendar.date(byAdding: .weekOfYear,
                                      value: -(weeks - 1),
                                      to: currentWeekStart) ?? currentWeekStart
        let gridEnd = calendar.date(byAdding: .weekOfYear,
                                    value: weeks,
                                    to: gridStart) ?? endDate

        var observedByDay: [Date: Double] = [:]
        var previousWindow: LimitWindow?

        for sample in samples
            .filter({ $0.accountID == accountID && $0.snapshot.fetchedAt < gridEnd })
            .sorted(by: { $0.snapshot.fetchedAt < $1.snapshot.fetchedAt }) {
            guard let window = sample.snapshot.windows.first(where: { $0.id == windowID }) else {
                // The window was absent from this snapshot, so consumption and
                // rollovers after it are unobservable. Drop the baseline rather
                // than attribute a cross-gap difference to a single day.
                previousWindow = nil
                continue
            }

            if let previousWindow {
                let delta: Double
                if cycleChanged(from: previousWindow, to: window) {
                    // The first observation in a new cycle already includes
                    // any consumption since the reset.
                    delta = max(0, window.usedPercent)
                } else {
                    // Negative changes without a known rollover are provider
                    // corrections and must not appear as usage.
                    delta = max(0, window.usedPercent - previousWindow.usedPercent)
                }

                let day = calendar.startOfDay(for: sample.snapshot.fetchedAt)
                if day >= gridStart && day < gridEnd && delta >= 0.05 {
                    observedByDay[day, default: 0] += delta
                }
            }
            previousWindow = window
        }

        return (0..<(weeks * 7)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }
            return UsageActivityDay(
                date: date,
                observedUsedPercent: observedByDay[date, default: 0],
                isFuture: date > today)
        }
    }

    public static func trendPoints(
        samples: [UsageHistorySample],
        accountID: UUID,
        windowID: String,
        since startDate: Date
    ) -> [UsageTrendPoint] {
        var points: [UsageTrendPoint] = []
        var previousWindow: LimitWindow?

        for sample in samples
            .filter({ $0.accountID == accountID })
            .sorted(by: { $0.snapshot.fetchedAt < $1.snapshot.fetchedAt }) {
            guard let window = sample.snapshot.windows.first(where: { $0.id == windowID }) else {
                // Same continuity break as the activity grid: the first
                // observation after a gap is a new baseline, never a reset.
                previousWindow = nil
                continue
            }

            if sample.snapshot.fetchedAt >= startDate {
                points.append(
                    UsageTrendPoint(
                        date: sample.snapshot.fetchedAt,
                        remainingPercent: window.remainingPercent,
                        resetOccurred: previousWindow.map { cycleChanged(from: $0, to: window) } ?? false
                    )
                )
            }
            previousWindow = window
        }
        return points
    }

    private static func cycleChanged(from previous: LimitWindow, to current: LimitWindow) -> Bool {
        switch (previous.resetsAt, current.resetsAt) {
        case let (old?, new?):
            return new.timeIntervalSince(old) > 60
                && current.usedPercent + 0.05 < previous.usedPercent
        case (nil, nil):
            return current.usedPercent + 0.05 < previous.usedPercent
        case (nil, _?):
            return current.usedPercent + 0.05 < previous.usedPercent
        case (_?, nil):
            return false
        }
    }
}
