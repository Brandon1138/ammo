import Foundation
import UsageKit

/// Latest raw usage response per account. Only response bodies from the four
/// read-only usage endpoints enter this store; request headers and token
/// endpoint responses never cross this boundary.
enum RawUsagePayloadStore {
    struct Capture: Codable, Sendable {
        let accountID: UUID
        let provider: ProviderID
        let fetchedAt: Date
        let body: Data
    }

    private static var fileURL: URL {
        AppGroup.containerURL.appendingPathComponent("raw-usage-payloads.json")
    }

    private static var lock: SharedFileLock {
        SharedFileLock(url: AppGroup.containerURL.appendingPathComponent("raw-usage-payloads.lock"))
    }

    static func record(body: Data, accountID: UUID, provider: ProviderID, at date: Date = .now) {
        guard !AccountDeletionStore.isDeleted(accountID) else { return }
        do {
            try lock.withLock {
                guard !AccountDeletionStore.isDeleted(accountID) else { return }
                var captures = loadUnlocked()
                captures.removeAll { $0.accountID == accountID && $0.provider == provider }
                captures.append(Capture(accountID: accountID,
                                        provider: provider,
                                        fetchedAt: date,
                                        body: body))
                try saveUnlocked(captures)
            }
        } catch {
            AmmoLog.sharedStore.error("Unable to retain raw usage payload: \(String(describing: error), privacy: .private)")
        }
    }

    static func remove(accountID: UUID) throws {
        try lock.withLock {
            var captures = loadUnlocked()
            captures.removeAll { $0.accountID == accountID }
            try saveUnlocked(captures)
        }
    }

    static func load() -> [Capture] {
        (try? lock.withLock { loadUnlocked() }) ?? []
    }

    /// Builds one shareable JSON file. Each `body` value is the exact UTF-8
    /// response body, escaped only by the outer export document's JSON encoder.
    /// No URLRequest or HTTPURLResponse object is retained or exported.
    static func makeExportFile() throws -> URL {
        // Deletion prunes the store, but that prune is best effort. Re-check
        // against the live accounts so a payload for a removed account can
        // never leave the device even if its prune failed.
        let live = Set(SharedStore.load().map(\.account.id))
        let captures = load().filter { live.contains($0.accountID) }
        guard !captures.isEmpty else { throw ExportError.noPayloads }
        let data = try exportData(captures: captures)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ammo-raw-usage-\(formatter.string(from: .now)).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func exportData(captures: [Capture], exportedAt: Date = .now) throws -> Data {
        let captures = captures.sorted {
            if $0.provider.rawValue != $1.provider.rawValue {
                return $0.provider.rawValue < $1.provider.rawValue
            }
            return $0.accountID.uuidString < $1.accountID.uuidString
        }
        let export = ExportDocument(
            exportedAt: exportedAt,
            payloads: captures.map {
                ExportPayload(accountID: $0.accountID,
                              provider: $0.provider,
                              fetchedAt: $0.fetchedAt,
                              body: String(decoding: $0.body, as: UTF8.self))
            })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(export)
    }

    private static func loadUnlocked() -> [Capture] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Capture].self, from: data)) ?? []
    }

    private static func saveUnlocked(_ captures: [Capture]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(captures).write(to: fileURL, options: .atomic)
    }

    private struct ExportDocument: Encodable {
        let exportedAt: Date
        let payloads: [ExportPayload]
    }

    private struct ExportPayload: Encodable {
        let accountID: UUID
        let provider: ProviderID
        let fetchedAt: Date
        let body: String
    }

    enum ExportError: LocalizedError {
        case noPayloads

        var errorDescription: String? {
            "No raw usage payloads have been captured yet. Refresh an account first."
        }
    }
}

/// Captures only a successful response from one exact usage URL. Authentication
/// headers remain inside URLSession and are discarded with the request.
struct PayloadCapturingTransport: HTTPTransport {
    let accountID: UUID
    let provider: ProviderID
    let usageURL: URL
    private let base = URLSessionTransport()

    func request(_ request: URLRequest) async throws -> (Data, Int) {
        let result = try await base.request(request)
        if Self.shouldCapture(request: request, status: result.1, usageURL: usageURL) {
            RawUsagePayloadStore.record(body: result.0,
                                        accountID: accountID,
                                        provider: provider)
        }
        return result
    }

    static func shouldCapture(request: URLRequest, status: Int, usageURL: URL) -> Bool {
        request.url == usageURL && (200..<300).contains(status)
    }
}
