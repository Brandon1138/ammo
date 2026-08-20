import Foundation
import Testing
import UsageKit
@testable import Ammo

/// Lock Screen gauge selection with Codex Spark meters present. The neutral
/// UsageKit rule ignores model-scoped windows entirely; the one refinement —
/// Spark's session meter driving the ring on Pro plans — lives in the app
/// layer and is exercised here.
@MainActor
@Suite("Lock Screen gauge with Spark")
struct LockScreenGaugeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Pro plan with Spark shown fills the ring from Spark session, number stays Weekly")
    func proPlanUsesSparkSessionRing() throws {
        let presentation = try #require(state(plan: "prolite", windows: [
            window(.weekly, "Weekly", used: 100),
            window(.modelScoped, "Spark session", used: 5),
            window(.modelScoped, "Spark weekly", used: 2),
        ]).lockScreenUsagePresentation)

        #expect(presentation.indicatorWindow.label == "Spark session")
        #expect(presentation.numericWindow?.label == "Weekly")
    }

    @Test("The 20x tier gets the same ring as the 5x tier")
    func proTierAlsoUsesSparkSessionRing() throws {
        let presentation = try #require(state(plan: "pro", windows: [
            window(.weekly, "Weekly", used: 40),
            window(.modelScoped, "Spark session", used: 5),
        ]).lockScreenUsagePresentation)

        #expect(presentation.indicatorWindow.label == "Spark session")
        #expect(presentation.numericWindow?.label == "Weekly")
    }

    @Test("A cached snapshot with the pre-rename label still drives the ring")
    func legacySparkLabelStillDrivesTheRing() throws {
        let presentation = try #require(state(plan: "prolite", windows: [
            window(.weekly, "Weekly", used: 40),
            window(.modelScoped, "Spark", used: 5),
        ]).lockScreenUsagePresentation)

        #expect(presentation.indicatorWindow.label == "Spark")
        #expect(presentation.numericWindow?.label == "Weekly")
    }

    @Test("A plan with a real session window keeps it as the ring")
    func realSessionWindowIsNeverDisplaced() throws {
        let presentation = try #require(state(plan: "plus", windows: [
            window(.session, "Session", used: 30),
            window(.weekly, "Weekly", used: 40),
            window(.modelScoped, "Spark session", used: 5),
        ]).lockScreenUsagePresentation)

        #expect(presentation.indicatorWindow.kind == .session)
        #expect(presentation.numericWindow?.label == "Weekly")
    }

    @Test("Business plans keep the neutral marker gauge")
    func businessPlanKeepsNeutralSelection() throws {
        let presentation = try #require(state(
            plan: "self_serve_business_usage_based",
            windows: [
                window(.weekly, "Weekly", used: 40),
                window(.modelScoped, "Spark session", used: 5),
            ]).lockScreenUsagePresentation)

        #expect(presentation.indicatorWindow.label == "Weekly")
        #expect(presentation.numericWindow == nil)
    }

    @Test("Spark hidden restores the marker gauge on the Weekly window")
    func hiddenSparkRestoresMarkerGauge() throws {
        let presentation = try #require(state(plan: "prolite", windows: [
            window(.weekly, "Weekly", used: 100),
        ]).lockScreenUsagePresentation)

        #expect(presentation.indicatorWindow.label == "Weekly")
        #expect(presentation.numericWindow == nil)
    }

    private func state(plan: String?, windows: [LimitWindow]) -> AccountState {
        AccountState(
            account: StoredAccount(provider: .codex, label: "Codex"),
            snapshot: UsageSnapshot(
                provider: .codex, plan: plan, windows: windows, fetchedAt: now),
            lastError: nil,
            updatedAt: now)
    }

    private func window(
        _ kind: WindowKind, _ label: String, used: Double
    ) -> LimitWindow {
        LimitWindow(kind: kind, label: label, usedPercent: used, resetsAt: nil)
    }
}
