import Foundation
import Testing

@testable import UsageKit

@Suite("OpenRouter key presentation")
struct OpenRouterKeyPresentationTests {
    private let now = ISO8601DateFormatter().date(from: "2026-08-19T12:34:56Z")!

    @Test("A budgeted key meters remaining credits against its period")
    func budgetedKey() throws {
        let presentation = try #require(
            OpenRouterKeyPresentation(snapshot: budgetedSnapshot()))

        #expect(presentation.headline == "\(money(74.5)) left")
        #expect(presentation.detail.hasPrefix("\(money(25.5)) of \(money(100))"))
        #expect(presentation.detail.hasSuffix("used this month"))
        #expect(presentation.cadence == .monthly)
        #expect(presentation.remainingFraction == 0.745)
        #expect(presentation.resetsAt != nil)
        #expect(presentation.dailyDetail == nil)
        #expect(!presentation.isExhausted)
        #expect(presentation.hasBudget)
    }

    @Test("Daily and weekly budgets name their own period")
    func shorterCadences() throws {
        let daily = try #require(OpenRouterKeyPresentation(
            snapshot: budgetedSnapshot(
                periodStart: "2026-08-19T00:00:00Z",
                resetsAt: "2026-08-20T00:00:00Z")))
        let weekly = try #require(OpenRouterKeyPresentation(
            snapshot: budgetedSnapshot(
                periodStart: "2026-08-17T00:00:00Z",
                resetsAt: "2026-08-24T00:00:00Z")))

        #expect(daily.cadence == .daily)
        #expect(daily.detail.hasSuffix("used today"))
        #expect(weekly.cadence == .weekly)
        #expect(weekly.detail.hasSuffix("used this week"))
    }

    @Test("A key without a persisted period drops the phrase instead of guessing")
    func unknownCadence() throws {
        let presentation = try #require(OpenRouterKeyPresentation(
            snapshot: budgetedSnapshot(periodStart: nil)))

        #expect(presentation.cadence == nil)
        #expect(presentation.detail.hasSuffix("used"))
    }

    @Test("A pay-as-you-go key shows spend to date and today's spend")
    func payAsYouGo() throws {
        let presentation = try #require(
            OpenRouterKeyPresentation(snapshot: unlimitedSnapshot()))

        #expect(presentation.headline == "Pay-as-you-go")
        #expect(presentation.detail == "\(money(50)) spent to date")
        #expect(presentation.dailyDetail == "\(money(1.25)) today")
        #expect(presentation.remainingFraction == nil)
        #expect(presentation.resetsAt == nil)
        #expect(!presentation.hasBudget)
    }

    @Test("A pay-as-you-go key without a daily aggregate omits that line")
    func payAsYouGoWithoutDaily() throws {
        let presentation = try #require(
            OpenRouterKeyPresentation(snapshot: unlimitedSnapshot(daily: nil)))

        #expect(presentation.dailyDetail == nil)
    }

    @Test("The tier badge is entitlement copy, and absent when unreported")
    func tierBadges() {
        #expect(OpenRouterKeyPresentation.tierBadge(isFreeTier: true)
            == "Free tier · 50 free req/day cap")
        #expect(OpenRouterKeyPresentation.tierBadge(isFreeTier: false)
            == "1000 free req/day cap")
        #expect(OpenRouterKeyPresentation.tierBadge(isFreeTier: nil) == nil)
    }

    @Test("An exhausted budget is reported as exhausted")
    func exhaustedBudget() throws {
        let presentation = try #require(
            OpenRouterKeyPresentation(snapshot: budgetedSnapshot(remaining: 0, used: 100)))

        #expect(presentation.isExhausted)
        #expect(presentation.remainingFraction == 0)
    }

    @Test("Other providers never render as an OpenRouter key")
    func otherProvidersRejected() {
        let snapshot = UsageSnapshot(
            provider: .codex,
            plan: nil,
            windows: [],
            onDemand: [],
            fetchedAt: now)

        #expect(OpenRouterKeyPresentation(snapshot: snapshot) == nil)
    }

    @Test("An OpenRouter snapshot with no reported pool renders nothing")
    func missingPool() {
        let snapshot = UsageSnapshot(
            provider: .openRouter,
            plan: nil,
            windows: [],
            onDemand: [],
            fetchedAt: now)

        #expect(OpenRouterKeyPresentation(snapshot: snapshot) == nil)
    }

    // MARK: - Fixtures

    private func budgetedSnapshot(
        remaining: Double = 74.5,
        used: Double = 25.5,
        periodStart: String? = "2026-08-01T00:00:00Z",
        resetsAt: String? = "2026-09-01T00:00:00Z",
        isFreeTier: Bool? = false
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: .openRouter,
            plan: nil,
            windows: [],
            onDemand: [
                OnDemandUsage(
                    id: "openrouter-key-spending",
                    label: "API key spending",
                    kind: .spendingLimit,
                    scope: .personal,
                    isEnabled: true,
                    isUnlimited: false,
                    used: used,
                    limit: 100,
                    remaining: remaining,
                    periodStart: periodStart.flatMap(utcDate),
                    resetsAt: resetsAt.flatMap(utcDate)),
            ],
            isFreeTier: isFreeTier,
            fetchedAt: now)
    }

    private func unlimitedSnapshot(daily: Double? = 1.25) -> UsageSnapshot {
        var pools = [
            OnDemandUsage(
                id: "openrouter-key-spending",
                label: "API key spending",
                kind: .spendingLimit,
                scope: .personal,
                isEnabled: true,
                isUnlimited: true,
                used: 50),
        ]
        if let daily {
            pools.append(OnDemandUsage(
                id: "openrouter-key-daily-spend",
                label: "Spend today",
                kind: .spendingLimit,
                scope: .personal,
                isEnabled: true,
                isUnlimited: true,
                used: daily,
                periodStart: utcDate("2026-08-19T00:00:00Z")))
        }
        return UsageSnapshot(
            provider: .openRouter,
            plan: nil,
            windows: [],
            onDemand: pools,
            isFreeTier: true,
            fetchedAt: now)
    }

    private func utcDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    /// Currency copy is locale-formatted; assertions compare against the same
    /// formatter rather than hard-coding one locale's output.
    private func money(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
}
