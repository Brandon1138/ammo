import Foundation
import UsageKit

/// App-group display preferences shared by the app and the widget extension.
///
/// These decide what is *drawn*, never what is fetched. Ingestion always parses
/// every window a provider reports, so flipping a switch here re-renders the
/// cache that is already on disk — no refetch, and no data loss if it is turned
/// back on later. The marker-file storage mirrors `DemoModeStore` so the widget
/// extension can read the value without an IPC hop.
enum UsageDisplayPreferences {
    private static var codexSparkMarkerURL: URL {
        AppGroup.containerURL.appendingPathComponent("codex-spark-metering-enabled")
    }

    /// Off by default: someone who never uses Spark keeps the four-provider
    /// board and the account rows they already have.
    static var showsCodexSpark: Bool {
        FileManager.default.fileExists(atPath: codexSparkMarkerURL.path)
    }

    static func setShowsCodexSpark(_ enabled: Bool) throws {
        let url = codexSparkMarkerURL
        if enabled {
            try Data().write(to: url, options: .atomic)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Presentation filter

    /// Strips windows the current preferences hide. Applied at the cache-read
    /// seam every surface shares, and never on a write path, so the persisted
    /// snapshot keeps its full set of windows.
    static func presented(_ states: [AccountState],
                          showingCodexSpark: Bool = showsCodexSpark) -> [AccountState] {
        guard !showingCodexSpark else { return states }
        return states.map { state in
            guard let snapshot = state.snapshot,
                  snapshot.windows.contains(where: \.isCodexSparkWindow) else { return state }
            var hidden = state
            hidden.snapshot = presented(snapshot, showingCodexSpark: showingCodexSpark)
            return hidden
        }
    }

    static func presented(_ snapshot: UsageSnapshot,
                          showingCodexSpark: Bool = showsCodexSpark) -> UsageSnapshot {
        guard !showingCodexSpark else { return snapshot }
        return UsageSnapshot(provider: snapshot.provider,
                             plan: snapshot.plan,
                             windows: snapshot.windows.filter { !$0.isCodexSparkWindow },
                             resetCreditsAvailable: snapshot.resetCreditsAvailable,
                             onDemand: snapshot.onDemand,
                             isFreeTier: snapshot.isFreeTier,
                             fetchedAt: snapshot.fetchedAt)
    }
}

extension LimitWindow {
    /// Codex names its Spark bucket; Ammo never invents one. This is the single
    /// place the presented label is matched, mirroring `isFableModelWindow`.
    var isCodexSparkWindow: Bool {
        guard kind == .modelScoped else { return false }
        return label == "Spark" || label.hasPrefix("Spark ")
    }
}
