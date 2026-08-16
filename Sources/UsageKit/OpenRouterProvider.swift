import Foundation

/// Least-privilege OpenRouter adapter.
///
/// This provider accepts an ordinary inference API key and calls only the
/// documented current-key endpoint. It deliberately does not use Management
/// keys, account-wide credits, analytics, or inference endpoints.
public struct OpenRouterProvider: UsageProvider {
    public let id = ProviderID.openRouter

    public static let usageURL = URL(string: "https://openrouter.ai/api/v1/key")!

    let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func fetchUsage(tokens: OAuthTokens) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.usageURL)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, status) = try await transport.request(request)
        switch status {
        case 200..<300:
            break
        case 401, 403:
            // Do not retain or log the authenticated error payload.
            throw UsageError.notAuthenticated("openrouter: API key was rejected")
        case 429:
            throw UsageError.http(status: status, body: "OpenRouter throttled the usage request")
        default:
            throw UsageError.http(status: status, body: "OpenRouter usage request failed")
        }

        let response: Response
        do {
            response = try Self.decoder.decode(Response.self, from: data)
        } catch {
            // Decoding diagnostics contain field paths, never the response body.
            throw UsageError.malformedResponse("openrouter key usage: \(error)")
        }
        return try Self.snapshot(from: response, at: Date())
    }

    /// OpenRouter API keys are long-lived imported credentials. The shared
    /// coordinator skips this method because imported accounts are explicitly
    /// non-refreshable; this failure prevents accidental rotation semantics if
    /// a future caller violates that invariant.
    public func refresh(tokens: OAuthTokens) async throws -> OAuthTokens {
        throw UsageError.notAuthenticated("openrouter: imported API keys cannot be refreshed")
    }

    public static func importedTokens(from rawKey: String) throws -> OAuthTokens {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw UsageError.notAuthenticated("openrouter: API key is empty")
        }
        return OAuthTokens(accessToken: key)
    }

    // MARK: - Response mapping

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    struct Response: Decodable {
        struct KeyData: Decodable {
            let label: String
            let limit: Double?
            let limitRemaining: Double?
            let limitReset: String?
            let usage: Double
            let usageDaily: Double
            let usageWeekly: Double
            let usageMonthly: Double
            let byokUsage: Double
            let byokUsageDaily: Double
            let byokUsageWeekly: Double
            let byokUsageMonthly: Double
            let includeByokInLimit: Bool
            let isManagementKey: Bool
            let isProvisioningKey: Bool
        }

        let data: KeyData
    }

    static func snapshot(from response: Response, at fetchedAt: Date) throws -> UsageSnapshot {
        let key = response.data
        guard !key.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UsageError.malformedResponse("openrouter key usage: missing key label")
        }
        guard !key.isManagementKey, !key.isProvisioningKey else {
            throw UsageError.notAuthenticated(
                "openrouter: Management API keys are not accepted; import an ordinary inference key")
        }

        let values = [
            key.usage,
            key.usageDaily,
            key.usageWeekly,
            key.usageMonthly,
            key.byokUsage,
            key.byokUsageDaily,
            key.byokUsageWeekly,
            key.byokUsageMonthly,
        ]
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }),
            key.limit.map({ $0.isFinite && $0 >= 0 }) ?? true,
            key.limitRemaining.map({ $0.isFinite && $0 >= 0 }) ?? true
        else {
            throw UsageError.malformedResponse("openrouter key usage: invalid monetary value")
        }

        let cadence = key.limitReset?.lowercased()
        let providerUsage: Double
        let byokUsage: Double
        switch cadence {
        case "daily":
            providerUsage = key.usageDaily
            byokUsage = key.byokUsageDaily
        case "weekly":
            providerUsage = key.usageWeekly
            byokUsage = key.byokUsageWeekly
        case "monthly":
            providerUsage = key.usageMonthly
            byokUsage = key.byokUsageMonthly
        default:
            providerUsage = key.usage
            byokUsage = key.byokUsage
        }
        let used = providerUsage + (key.includeByokInLimit ? byokUsage : 0)
        guard used.isFinite else {
            throw UsageError.malformedResponse("openrouter key usage: invalid combined usage")
        }

        let hasLimit = key.limit != nil
        let usage = OnDemandUsage(
            id: "openrouter-key-spending",
            label: "API key spending",
            kind: .spendingLimit,
            scope: .personal,
            isEnabled: true,
            isUnlimited: !hasLimit,
            unit: .currency,
            dataSource: .providerUsageResponse,
            currencyCode: "USD",
            used: used,
            limit: key.limit,
            remaining: hasLimit ? key.limitRemaining : nil,
            resetsAt: hasLimit ? nextReset(for: cadence, after: fetchedAt) : nil)

        return UsageSnapshot(
            provider: .openRouter,
            plan: nil,
            windows: [],
            onDemand: [usage],
            fetchedAt: fetchedAt)
    }

    /// OpenRouter documents daily midnight, Monday-start weekly, and first-day
    /// monthly boundaries in UTC. Unknown future cadence strings intentionally
    /// produce no timestamp instead of guessing.
    static func nextReset(for cadence: String?, after date: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startOfDay = calendar.startOfDay(for: date)

        switch cadence {
        case "daily":
            return calendar.date(byAdding: .day, value: 1, to: startOfDay)
        case "weekly":
            let weekday = calendar.component(.weekday, from: startOfDay)
            let offset = (9 - weekday) % 7
            return calendar.date(byAdding: .day, value: offset == 0 ? 7 : offset, to: startOfDay)
        case "monthly":
            let components = calendar.dateComponents([.year, .month], from: startOfDay)
            guard let firstOfMonth = calendar.date(from: components) else { return nil }
            return calendar.date(byAdding: .month, value: 1, to: firstOfMonth)
        default:
            return nil
        }
    }
}
