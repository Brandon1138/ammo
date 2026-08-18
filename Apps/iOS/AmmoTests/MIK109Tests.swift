import Foundation
import Testing
import UsageKit

@testable import Ammo

@MainActor
@Suite("MIK-109 widget Fable and raw payload capture", .serialized)
struct MIK109Tests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Widget presentations consume the parsed Fable window")
    func widgetUsesParsedFableWindow() throws {
        let fable = LimitWindow(kind: .modelScoped,
                                label: "Fable",
                                usedPercent: 52,
                                resetsAt: now.addingTimeInterval(86_400))
        let state = AccountState(
            account: StoredAccount(provider: .claude, label: "Claude"),
            snapshot: UsageSnapshot(
                provider: .claude,
                plan: "max",
                windows: [
                    LimitWindow(kind: .session, label: "Session", usedPercent: 95,
                                resetsAt: now.addingTimeInterval(3_600)),
                    LimitWindow(kind: .weekly, label: "Weekly", usedPercent: 47,
                                resetsAt: now.addingTimeInterval(86_400)),
                    LimitWindow(kind: .modelScoped, label: "Opus", usedPercent: 12,
                                resetsAt: now.addingTimeInterval(86_400)),
                    fable,
                ],
                fetchedAt: now),
            lastError: nil,
            updatedAt: now)

        // Fable leads; the provider's own ordering survives behind it.
        #expect(state.widgetModelScopedWindows.map(\.label) == ["Fable", "Opus"])
        // Session is the worst window here, so the compact surfaces have a
        // model bucket to add that is not already their headline meter.
        #expect(state.widgetCompactModelWindow == fable)
        #expect(state.snapshot?.widgetWindowGroups(limitedTo: WidgetProviderPanels.boardWindowLimit)
            .flatMap { $0 }.contains(fable) == true)
        #expect(state.snapshot?.widgetWindowGroups(limitedTo: WidgetProviderPanels.boardWindowLimit)
            .flatMap { $0 }.map(\.label) == ["Session", "Weekly", "Fable"])
    }

    @Test("A model bucket that is already the headline meter is not repeated")
    func headlineModelBucketIsNotDuplicated() {
        let fable = LimitWindow(kind: .modelScoped, label: "Fable", usedPercent: 95,
                                resetsAt: now.addingTimeInterval(86_400))
        let state = AccountState(
            account: StoredAccount(provider: .claude, label: "Claude"),
            snapshot: UsageSnapshot(provider: .claude, plan: "max", windows: [
                LimitWindow(kind: .session, label: "Session", usedPercent: 10,
                            resetsAt: now.addingTimeInterval(3_600)),
                fable,
            ], fetchedAt: now),
            lastError: nil,
            updatedAt: now)

        #expect(state.widgetPercentageWindow == fable)
        #expect(state.widgetCompactModelWindow == nil)
    }

    @Test("Missing Fable produces no widget placeholder")
    func noFableCollapsesCleanly() {
        let withFable = claudeState(modelWindow: LimitWindow(
            kind: .modelScoped,
            label: "Fable",
            usedPercent: 52,
            resetsAt: now.addingTimeInterval(86_400)))
        let withoutFable = claudeState(modelWindow: nil)

        #expect(withFable.widgetModelScopedWindows.map(\.label) == ["Fable"])
        #expect(withoutFable.widgetModelScopedWindows.isEmpty)
        #expect(withoutFable.widgetCompactModelWindow == nil)
        #expect(withoutFable.snapshot?.widgetWindowGroups(limitedTo: 3)
            .flatMap { $0 }.count == 2)
        #expect(withoutFable.snapshot?.windows.map(\.label) == ["Session", "Weekly"])
    }

    @Test("Capture export contains bodies but no HTTP headers")
    func payloadExportIsBodyOnly() throws {
        let capture = RawUsagePayloadStore.Capture(
            accountID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            provider: .claude,
            fetchedAt: now,
            body: Data(#"{"limits":[{"kind":"weekly_scoped"}]}"#.utf8))
        let data = try RawUsagePayloadStore.exportData(captures: [capture], exportedAt: now)
        let export = String(decoding: data, as: UTF8.self)

        #expect(export.contains("weekly_scoped"))
        #expect(!export.localizedCaseInsensitiveContains("authorization"))
        #expect(!export.localizedCaseInsensitiveContains("bearer"))
        #expect(!export.localizedCaseInsensitiveContains("cookie"))
    }

    @Test("Capture transport accepts only successful exact usage endpoints")
    func captureEndpointIsFailClosed() {
        let usageURL = ClaudeProvider.usageURL
        var usageRequest = URLRequest(url: usageURL)
        usageRequest.setValue("Bearer secret", forHTTPHeaderField: "Authorization")

        #expect(PayloadCapturingTransport.shouldCapture(
            request: usageRequest, status: 200, usageURL: usageURL))
        #expect(!PayloadCapturingTransport.shouldCapture(
            request: usageRequest, status: 401, usageURL: usageURL))
        #expect(!PayloadCapturingTransport.shouldCapture(
            request: URLRequest(url: ClaudeProvider.tokenURL),
            status: 200,
            usageURL: usageURL))
    }

    @Test("Deleting an account drops its captured payload")
    func deletingAnAccountDropsItsCapture() throws {
        let account = StoredAccount(provider: .claude, label: "Capture")
        try SharedStore.insert(AccountState(account: account))
        defer { try? SharedStore.remove(id: account.id) }

        RawUsagePayloadStore.record(body: Data(#"{"marker":"kept"}"#.utf8),
                                    accountID: account.id,
                                    provider: .claude)
        #expect(RawUsagePayloadStore.load().contains { $0.accountID == account.id })

        try SharedStore.remove(id: account.id)
        #expect(!RawUsagePayloadStore.load().contains { $0.accountID == account.id })
    }

    @Test("An orphaned capture never reaches the export")
    func orphanedCaptureIsNotExported() throws {
        let orphan = UUID()
        defer { try? RawUsagePayloadStore.remove(accountID: orphan) }
        RawUsagePayloadStore.record(body: Data(#"{"marker":"orphan"}"#.utf8),
                                    accountID: orphan,
                                    provider: .claude)
        #expect(RawUsagePayloadStore.load().contains { $0.accountID == orphan })

        // The orphan has no live account, so the export either omits it or
        // reports that there is nothing to share.
        do {
            let url = try RawUsagePayloadStore.makeExportFile()
            defer { try? FileManager.default.removeItem(at: url) }
            let export = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            #expect(!export.contains("orphan"))
        } catch RawUsagePayloadStore.ExportError.noPayloads {
            // Nothing live to export; the orphan stayed on the device.
        }
    }

    private func claudeState(modelWindow: LimitWindow?) -> AccountState {
        var windows = [
            LimitWindow(kind: .session, label: "Session", usedPercent: 95,
                        resetsAt: now.addingTimeInterval(3_600)),
            LimitWindow(kind: .weekly, label: "Weekly", usedPercent: 47,
                        resetsAt: now.addingTimeInterval(86_400)),
        ]
        if let modelWindow { windows.append(modelWindow) }
        return AccountState(
            account: StoredAccount(provider: .claude, label: "Claude"),
            snapshot: UsageSnapshot(provider: .claude,
                                    plan: modelWindow == nil ? "pro" : "max",
                                    windows: windows,
                                    fetchedAt: now),
            lastError: nil,
            updatedAt: now)
    }
}
