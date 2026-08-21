import Foundation
import Testing
@testable import UsageKit

@Suite struct LockScreenUsagePresentationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func dualWindowProviderUsesSessionIndicatorAndWeeklyNumber() throws {
        let snapshot = UsageSnapshot(
            provider: .claude,
            plan: nil,
            windows: [
                window(.weekly, "Weekly", used: 40),
                window(.modelScoped, "Opus", used: 70),
                window(.session, "Session", used: 20),
            ],
            fetchedAt: now)

        let presentation = try #require(LockScreenUsagePresentation(snapshot: snapshot))

        #expect(presentation.indicatorWindow.kind == .session)
        #expect(presentation.numericWindow?.kind == .weekly)
    }

    @Test func singleWindowProviderDoesNotFabricateSessionWindow() throws {
        let snapshot = UsageSnapshot(
            provider: .codex,
            plan: "plus",
            windows: [window(.weekly, "Weekly", used: 35)],
            fetchedAt: now)

        let presentation = try #require(LockScreenUsagePresentation(snapshot: snapshot))

        #expect(presentation.indicatorWindow.kind == .weekly)
        #expect(presentation.numericWindow == nil)
    }

    @Test func providerWithoutSessionUsesOnlyItsRealWindows() throws {
        let snapshot = UsageSnapshot(
            provider: .cursor,
            plan: "pro",
            windows: [
                window(.monthly, "Cursor Models", used: 25),
                window(.monthly, "Other Models", used: 10),
            ],
            fetchedAt: now)

        let presentation = try #require(LockScreenUsagePresentation(snapshot: snapshot))

        #expect(presentation.indicatorWindow.label == "Cursor Models")
        #expect(presentation.numericWindow?.label == "Other Models")
        #expect(![presentation.indicatorWindow, presentation.numericWindow].compactMap(\.self)
            .contains { $0.kind == .session })
    }

    @Test func modelScopedWindowsNeverClaimEitherSlot() throws {
        // Codex on Pro with Spark shown: one included window plus two Spark
        // buckets. The gauge must read exactly as it does without Spark.
        let snapshot = UsageSnapshot(
            provider: .codex,
            plan: "prolite",
            windows: [
                window(.weekly, "Weekly", used: 100),
                window(.modelScoped, "Spark session", used: 5),
                window(.modelScoped, "Spark weekly", used: 2),
            ],
            fetchedAt: now)

        let presentation = try #require(LockScreenUsagePresentation(snapshot: snapshot))

        #expect(presentation.indicatorWindow.label == "Weekly")
        #expect(presentation.numericWindow == nil)
    }

    @Test func allModelScopedSnapshotStillPresentsSomething() throws {
        let snapshot = UsageSnapshot(
            provider: .claude,
            plan: nil,
            windows: [window(.modelScoped, "Fable", used: 48)],
            fetchedAt: now)

        let presentation = try #require(LockScreenUsagePresentation(snapshot: snapshot))

        #expect(presentation.indicatorWindow.label == "Fable")
        #expect(presentation.numericWindow == nil)
    }

    @Test func explicitWindowChoiceIsPreservedVerbatim() {
        let spark = window(.modelScoped, "Spark session", used: 5)
        let weekly = window(.weekly, "Weekly", used: 100)

        let presentation = LockScreenUsagePresentation(
            indicatorWindow: spark, numericWindow: weekly, fetchedAt: now)

        #expect(presentation.indicatorWindow == spark)
        #expect(presentation.numericWindow == weekly)
    }

    @Test func freshnessBecomesStaleAfterTwoQuietIntervals() throws {
        let snapshot = UsageSnapshot(
            provider: .codex,
            plan: "plus",
            windows: [window(.weekly, "Weekly", used: 35)],
            fetchedAt: now)
        let presentation = try #require(LockScreenUsagePresentation(snapshot: snapshot))

        #expect(!presentation.isStale(
            at: now.addingTimeInterval(LockScreenUsagePresentation.staleAfter)))
        #expect(presentation.isStale(
            at: now.addingTimeInterval(LockScreenUsagePresentation.staleAfter + 1)))
    }

    private func window(
        _ kind: WindowKind,
        _ label: String,
        used: Double
    ) -> LimitWindow {
        LimitWindow(kind: kind, label: label, usedPercent: used, resetsAt: nil)
    }
}
