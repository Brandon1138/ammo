import Foundation
import Testing
@testable import UsageKit

struct UsageHistoryTests {
    private let accountID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }()

    @Test func activityIsResetAwareAndAssignedToObservationDay() {
        let firstReset = date("2026-07-27T00:00:00Z")
        let nextReset = date("2026-08-03T00:00:00Z")
        let samples = [
            sample(at: "2026-07-20T10:00:00Z", used: 10, resetsAt: firstReset),
            sample(at: "2026-07-21T10:00:00Z", used: 14, resetsAt: firstReset),
            sample(at: "2026-07-22T10:00:00Z", used: 3, resetsAt: nextReset),
        ]

        let days = UsageHistoryAnalysis.activityDays(
            samples: samples,
            accountID: accountID,
            windowID: "weekly:Weekly",
            endingAt: date("2026-07-22T12:00:00Z"),
            weekCount: 1,
            calendar: calendar
        )

        #expect(days.count == 7)
        #expect(activity(on: "2026-07-20T00:00:00Z", in: days) == 0)
        #expect(activity(on: "2026-07-21T00:00:00Z", in: days) == 4)
        #expect(activity(on: "2026-07-22T00:00:00Z", in: days) == 3)
    }

    @Test func providerCorrectionsAreNotCountedAsUsage() {
        let reset = date("2026-07-27T00:00:00Z")
        let samples = [
            sample(at: "2026-07-20T10:00:00Z", used: 40, resetsAt: reset),
            sample(at: "2026-07-21T10:00:00Z", used: 35, resetsAt: reset),
        ]

        let days = UsageHistoryAnalysis.activityDays(
            samples: samples,
            accountID: accountID,
            windowID: "weekly:Weekly",
            endingAt: date("2026-07-21T12:00:00Z"),
            weekCount: 1,
            calendar: calendar
        )

        #expect(days.allSatisfy { !$0.isActive })
    }

    @Test func activityGridKeepsGithubWeekTopology() {
        let days = UsageHistoryAnalysis.activityDays(
            samples: [],
            accountID: accountID,
            windowID: "weekly:Weekly",
            endingAt: date("2026-07-21T12:00:00Z"),
            weekCount: 7,
            calendar: calendar
        )

        #expect(days.count == 49)
        #expect(days.suffix(7).map(\.isFuture) == [false, false, false, true, true, true, true])
        #expect(calendar.component(.weekday, from: days[42].date) == 1)
    }

    @Test func trendMarksKnownReset() {
        let firstReset = date("2026-07-21T00:00:00Z")
        let nextReset = date("2026-07-28T00:00:00Z")
        let samples = [
            sample(at: "2026-07-20T10:00:00Z", used: 80, resetsAt: firstReset),
            sample(at: "2026-07-21T10:00:00Z", used: 5, resetsAt: nextReset),
        ]

        let points = UsageHistoryAnalysis.trendPoints(
            samples: samples,
            accountID: accountID,
            windowID: "weekly:Weekly",
            since: date("2026-07-20T00:00:00Z")
        )

        #expect(points.map(\.remainingPercent) == [20, 95])
        #expect(points.map(\.resetOccurred) == [false, true])
    }

    private func sample(at fetchedAt: String, used: Double, resetsAt: Date) -> UsageHistorySample {
        UsageHistorySample(
            accountID: accountID,
            snapshot: UsageSnapshot(
                provider: .claude,
                plan: nil,
                windows: [
                    LimitWindow(kind: .weekly,
                                label: "Weekly",
                                usedPercent: used,
                                resetsAt: resetsAt),
                ],
                fetchedAt: date(fetchedAt)
            )
        )
    }

    private func activity(on dateString: String, in days: [UsageActivityDay]) -> Double? {
        let target = date(dateString)
        return days.first(where: { $0.date == target })?.observedUsedPercent
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
