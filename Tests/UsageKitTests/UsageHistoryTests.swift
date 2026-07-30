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

    @Test func movingResetDeadlinesDoNotCreateResetMarkers() {
        let samples = [
            sample(at: "2026-07-20T10:00:00Z",
                   used: 10,
                   resetsAt: date("2026-07-27T00:00:00Z")),
            sample(at: "2026-07-21T10:00:00Z",
                   used: 10,
                   resetsAt: date("2026-07-28T00:00:00Z")),
            sample(at: "2026-07-22T10:00:00Z",
                   used: 14,
                   resetsAt: date("2026-07-29T00:00:00Z")),
        ]

        let points = UsageHistoryAnalysis.trendPoints(
            samples: samples,
            accountID: accountID,
            windowID: "weekly:Weekly",
            since: date("2026-07-20T00:00:00Z")
        )

        #expect(points.map(\.resetOccurred) == [false, false, false])
        #expect(points.filter(\.resetOccurred).isEmpty)
    }

    @Test func movingResetDeadlinesOnlyCountObservedIncreaseAsActivity() {
        let samples = [
            sample(at: "2026-07-20T10:00:00Z",
                   used: 10,
                   resetsAt: date("2026-07-27T00:00:00Z")),
            sample(at: "2026-07-21T10:00:00Z",
                   used: 10,
                   resetsAt: date("2026-07-28T00:00:00Z")),
            sample(at: "2026-07-22T10:00:00Z",
                   used: 14,
                   resetsAt: date("2026-07-29T00:00:00Z")),
        ]

        let days = UsageHistoryAnalysis.activityDays(
            samples: samples,
            accountID: accountID,
            windowID: "weekly:Weekly",
            endingAt: date("2026-07-22T12:00:00Z"),
            weekCount: 1,
            calendar: calendar
        )

        #expect(activity(on: "2026-07-21T00:00:00Z", in: days) == 0)
        #expect(activity(on: "2026-07-22T00:00:00Z", in: days) == 4)
        #expect(days.reduce(0) { $0 + $1.observedUsedPercent } == 4)
    }

    @Test func confirmedLaterCycleCreatesOneMarkerAndCorrectActivity() {
        let firstReset = date("2026-07-21T00:00:00Z")
        let nextReset = date("2026-07-28T00:00:00Z")
        let samples = [
            sample(at: "2026-07-20T10:00:00Z", used: 80, resetsAt: firstReset),
            sample(at: "2026-07-21T10:00:00Z", used: 5, resetsAt: nextReset),
            sample(at: "2026-07-22T10:00:00Z", used: 8, resetsAt: nextReset),
        ]

        let points = UsageHistoryAnalysis.trendPoints(
            samples: samples,
            accountID: accountID,
            windowID: "weekly:Weekly",
            since: date("2026-07-20T00:00:00Z")
        )
        let days = UsageHistoryAnalysis.activityDays(
            samples: samples,
            accountID: accountID,
            windowID: "weekly:Weekly",
            endingAt: date("2026-07-22T12:00:00Z"),
            weekCount: 1,
            calendar: calendar
        )

        #expect(points.filter(\.resetOccurred).count == 1)
        #expect(points.map(\.resetOccurred) == [false, true, false])
        #expect(activity(on: "2026-07-21T00:00:00Z", in: days) == 5)
        #expect(activity(on: "2026-07-22T00:00:00Z", in: days) == 3)
        #expect(days.reduce(0) { $0 + $1.observedUsedPercent } == 8)
    }

    @Test func nilResetTimestampsStillUseConsumptionDrop() {
        let samples = [
            sample(at: "2026-07-20T10:00:00Z", used: 40, resetsAt: nil),
            sample(at: "2026-07-21T10:00:00Z", used: 3, resetsAt: nil),
        ]

        let points = UsageHistoryAnalysis.trendPoints(
            samples: samples,
            accountID: accountID,
            windowID: "weekly:Weekly",
            since: date("2026-07-20T00:00:00Z")
        )

        #expect(points.map(\.resetOccurred) == [false, true])
    }

    @Test func windowGapDoesNotCreateResetMarkerOrActivityAcrossGap() {
        let samples = gapSamples(usedAfterGap: 5)

        let points = UsageHistoryAnalysis.trendPoints(
            samples: samples,
            accountID: accountID,
            windowID: sessionWindowID,
            since: date("2026-07-20T00:00:00Z")
        )
        let days = UsageHistoryAnalysis.activityDays(
            samples: samples,
            accountID: accountID,
            windowID: sessionWindowID,
            endingAt: date("2026-07-23T12:00:00Z"),
            weekCount: 1,
            calendar: calendar
        )

        #expect(points.map(\.remainingPercent) == [40, 95])
        #expect(points.map(\.resetOccurred) == [false, false])
        #expect(activity(on: "2026-07-23T00:00:00Z", in: days) == 0)
        #expect(days.allSatisfy { !$0.isActive })
    }

    @Test func windowGapDoesNotInflateActivityWhenUsageRoseUnobserved() {
        let samples = gapSamples(usedAfterGap: 80)

        let points = UsageHistoryAnalysis.trendPoints(
            samples: samples,
            accountID: accountID,
            windowID: sessionWindowID,
            since: date("2026-07-20T00:00:00Z")
        )
        let days = UsageHistoryAnalysis.activityDays(
            samples: samples,
            accountID: accountID,
            windowID: sessionWindowID,
            endingAt: date("2026-07-23T12:00:00Z"),
            weekCount: 1,
            calendar: calendar
        )

        #expect(points.map(\.remainingPercent) == [40, 20])
        #expect(points.map(\.resetOccurred) == [false, false])
        #expect(activity(on: "2026-07-23T00:00:00Z", in: days) == 0)
        #expect(days.allSatisfy { !$0.isActive })
    }

    @Test func firstContinuousObservationAfterGapResumesDeltaTracking() {
        let samples = gapSamples(usedAfterGap: 5) + [
            sample(at: "2026-07-23T14:00:00Z",
                   windows: [sessionWindow(used: 9, resetsAt: date("2026-07-23T15:00:00Z")),
                             weeklyWindow(used: 17, resetsAt: date("2026-07-27T00:00:00Z"))]),
        ]

        let points = UsageHistoryAnalysis.trendPoints(
            samples: samples,
            accountID: accountID,
            windowID: sessionWindowID,
            since: date("2026-07-20T00:00:00Z")
        )
        let days = UsageHistoryAnalysis.activityDays(
            samples: samples,
            accountID: accountID,
            windowID: sessionWindowID,
            endingAt: date("2026-07-23T12:00:00Z"),
            weekCount: 1,
            calendar: calendar
        )

        #expect(points.map(\.resetOccurred) == [false, false, false])
        #expect(activity(on: "2026-07-23T00:00:00Z", in: days) == 4)
        #expect(days.reduce(0) { $0 + $1.observedUsedPercent } == 4)
    }

    @Test func firstContinuousObservationAfterGapResumesResetDetection() {
        let samples = gapSamples(usedAfterGap: 70) + [
            sample(at: "2026-07-23T16:00:00Z",
                   windows: [sessionWindow(used: 4, resetsAt: date("2026-07-23T21:00:00Z")),
                             weeklyWindow(used: 17, resetsAt: date("2026-07-27T00:00:00Z"))]),
        ]

        let points = UsageHistoryAnalysis.trendPoints(
            samples: samples,
            accountID: accountID,
            windowID: sessionWindowID,
            since: date("2026-07-20T00:00:00Z")
        )
        let days = UsageHistoryAnalysis.activityDays(
            samples: samples,
            accountID: accountID,
            windowID: sessionWindowID,
            endingAt: date("2026-07-23T12:00:00Z"),
            weekCount: 1,
            calendar: calendar
        )

        #expect(points.map(\.resetOccurred) == [false, false, true])
        #expect(activity(on: "2026-07-23T00:00:00Z", in: days) == 4)
        #expect(days.reduce(0) { $0 + $1.observedUsedPercent } == 4)
    }

    @Test func otherWindowsKeepContinuityAcrossAnotherWindowsGap() {
        let samples = gapSamples(usedAfterGap: 5)

        let points = UsageHistoryAnalysis.trendPoints(
            samples: samples,
            accountID: accountID,
            windowID: "weekly:Weekly",
            since: date("2026-07-20T00:00:00Z")
        )
        let days = UsageHistoryAnalysis.activityDays(
            samples: samples,
            accountID: accountID,
            windowID: "weekly:Weekly",
            endingAt: date("2026-07-23T12:00:00Z"),
            weekCount: 1,
            calendar: calendar
        )

        #expect(points.map(\.remainingPercent) == [90, 88, 86, 84])
        #expect(points.allSatisfy { !$0.resetOccurred })
        #expect(activity(on: "2026-07-21T00:00:00Z", in: days) == 2)
        #expect(activity(on: "2026-07-22T00:00:00Z", in: days) == 2)
        #expect(activity(on: "2026-07-23T00:00:00Z", in: days) == 2)
        #expect(days.reduce(0) { $0 + $1.observedUsedPercent } == 6)
    }

    private let sessionWindowID = "session:Session"

    /// Session observed once, hidden by two weekly-only snapshots, then observed
    /// again — the shape OpenAI produced when the five-hour window disappeared.
    private func gapSamples(usedAfterGap: Double) -> [UsageHistorySample] {
        let weeklyReset = date("2026-07-27T00:00:00Z")
        return [
            sample(at: "2026-07-20T10:00:00Z",
                   windows: [sessionWindow(used: 60, resetsAt: date("2026-07-20T15:00:00Z")),
                             weeklyWindow(used: 10, resetsAt: weeklyReset)]),
            sample(at: "2026-07-21T10:00:00Z",
                   windows: [weeklyWindow(used: 12, resetsAt: weeklyReset)]),
            sample(at: "2026-07-22T10:00:00Z",
                   windows: [weeklyWindow(used: 14, resetsAt: weeklyReset)]),
            sample(at: "2026-07-23T10:00:00Z",
                   windows: [sessionWindow(used: usedAfterGap,
                                           resetsAt: date("2026-07-23T15:00:00Z")),
                             weeklyWindow(used: 16, resetsAt: weeklyReset)]),
        ]
    }

    private func sessionWindow(used: Double, resetsAt: Date?) -> LimitWindow {
        LimitWindow(kind: .session, label: "Session", usedPercent: used, resetsAt: resetsAt)
    }

    private func weeklyWindow(used: Double, resetsAt: Date?) -> LimitWindow {
        LimitWindow(kind: .weekly, label: "Weekly", usedPercent: used, resetsAt: resetsAt)
    }

    private func sample(at fetchedAt: String, windows: [LimitWindow]) -> UsageHistorySample {
        UsageHistorySample(
            accountID: accountID,
            snapshot: UsageSnapshot(
                provider: .codex,
                plan: nil,
                windows: windows,
                fetchedAt: date(fetchedAt)
            )
        )
    }

    private func sample(at fetchedAt: String, used: Double, resetsAt: Date?) -> UsageHistorySample {
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
