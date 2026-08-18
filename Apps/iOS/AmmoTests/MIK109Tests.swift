import Foundation
import Testing
import UsageKit

@testable import Ammo

@MainActor
@Suite("MIK-109 widget Fable and raw payload capture")
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

        #expect(state.widgetModelScopedWindows == [fable])
        #expect(state.snapshot?.widgetWindowGroups(limitedTo: WidgetProviderPanels.boardWindowLimit)
            .flatMap { $0 }.contains(fable) == true)
        #expect(state.snapshot?.widgetWindowGroups(limitedTo: WidgetProviderPanels.boardWindowLimit)
            .flatMap { $0 }.map(\.label) == ["Session", "Weekly", "Fable"])
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
