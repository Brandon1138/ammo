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

    /// Only `label` and `usage` are treated as contract. Every other field is
    /// optional so that one retired or renamed field cannot take every
    /// OpenRouter account offline at once; period aggregates fall back to the
    /// lifetime totals, and the key-class and tier flags fall back to
    /// "not reported".
    struct Response: Decodable {
        struct KeyData: Decodable {
            let label: String
            let limit: Double?
            let limitRemaining: Double?
            let limitReset: String?
            let usage: Double
            let usageDaily: Double?
            let usageWeekly: Double?
            let usageMonthly: Double?
            let byokUsage: Double?
            let byokUsageDaily: Double?
            let byokUsageWeekly: Double?
            let byokUsageMonthly: Double?
            let includeByokInLimit: Bool?
            /// Static entitlement flag: it selects the free-model request cap the
            /// key is subject to. It is not a counter, and free-model requests
            /// cost $0.00, so it never moves the monetary values above.
            let isFreeTier: TolerantFlag?
            let isManagementKey: Bool?
            let isProvisioningKey: Bool?
        }

        /// A flag whose only job is a label. A value of the wrong JSON type
        /// reads as unreported instead of failing the decode, because an account
        /// must never go offline over a cosmetic badge. The key-class flags are
        /// deliberately *not* tolerant: an unreadable `is_management_key` has to
        /// keep failing closed.
        struct TolerantFlag: Decodable, Equatable {
            let value: Bool?

            init(from decoder: any Decoder) throws {
                value = try? Bool(from: decoder)
            }
        }

        let data: KeyData
    }

    static func snapshot(from response: Response, at fetchedAt: Date) throws -> UsageSnapshot {
        let key = response.data
        guard !key.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UsageError.malformedResponse("openrouter key usage: missing key label")
        }
        // A key class the API declines to report cannot be proven safe, but the
        // provider only ever calls the read-only current-key endpoint, so an
        // unreported flag is accepted rather than failing the account.
        guard key.isManagementKey != true, key.isProvisioningKey != true else {
            throw UsageError.notAuthenticated(
                "openrouter: Management API keys are not accepted; import an ordinary inference key")
        }

        let cadence = key.limitReset?.lowercased()
        let totalByokUsage = key.byokUsage ?? 0
        let providerUsage: Double
        let byokUsage: Double
        switch cadence {
        case "daily":
            providerUsage = key.usageDaily ?? key.usage
            byokUsage = key.byokUsageDaily ?? totalByokUsage
        case "weekly":
            providerUsage = key.usageWeekly ?? key.usage
            byokUsage = key.byokUsageWeekly ?? totalByokUsage
        case "monthly":
            providerUsage = key.usageMonthly ?? key.usage
            byokUsage = key.byokUsageMonthly ?? totalByokUsage
        default:
            providerUsage = key.usage
            byokUsage = totalByokUsage
        }

        let values = [key.usage, totalByokUsage, providerUsage, byokUsage]
        // A negative remaining balance is a real over-spend state, not a
        // malformed payload; it is clamped below rather than rejected.
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }),
            key.limit.map({ $0.isFinite && $0 >= 0 }) ?? true,
            key.limitRemaining.map({ $0.isFinite }) ?? true
        else {
            throw UsageError.malformedResponse("openrouter key usage: invalid monetary value")
        }

        let used = providerUsage + ((key.includeByokInLimit ?? false) ? byokUsage : 0)
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
            remaining: hasLimit ? key.limitRemaining.map { max(0, $0) } : nil,
            periodStart: hasLimit ? periodStart(for: cadence, containing: fetchedAt) : nil,
            resetsAt: hasLimit ? nextReset(for: cadence, after: fetchedAt) : nil)

        var pools = [usage]
        if let today = dailySpend(key), !hasLimit {
            // A key with no budget has no period, so its headline spend is the
            // lifetime total. Today's reported spend is kept beside it rather
            // than folded into that total.
            pools.append(OnDemandUsage(
                id: "openrouter-key-daily-spend",
                label: "Spend today",
                kind: .spendingLimit,
                scope: .personal,
                isEnabled: true,
                isUnlimited: true,
                unit: .currency,
                dataSource: .providerUsageResponse,
                currencyCode: "USD",
                // No periodStart: nothing reads it here, and a value rolling over
                // at UTC midnight would register as a usage change and pull an
                // otherwise idle key into an extra refresh every day.
                used: today))
        }

        return UsageSnapshot(
            provider: .openRouter,
            plan: nil,
            windows: [],
            onDemand: pools,
            isFreeTier: key.isFreeTier?.value,
            fetchedAt: fetchedAt)
    }

    /// Today's spend in the same accounting the headline meter uses: BYOK is
    /// counted only where the key says BYOK counts. Absent daily aggregates
    /// yield no value rather than a total borrowed from another period.
    static func dailySpend(_ key: Response.KeyData) -> Double? {
        guard let usageDaily = key.usageDaily else { return nil }
        let byok = (key.includeByokInLimit ?? false) ? (key.byokUsageDaily ?? 0) : 0
        let total = usageDaily + byok
        guard total.isFinite, total >= 0 else { return nil }
        return total
    }

    /// Start of the budget period the key is currently inside, on the same UTC
    /// boundaries as `nextReset`. Persisting it lets display surfaces name the
    /// cadence exactly instead of inferring one from a countdown.
    static func periodStart(for cadence: String?, containing date: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startOfDay = calendar.startOfDay(for: date)

        switch cadence {
        case "daily":
            return startOfDay
        case "weekly":
            let weekday = calendar.component(.weekday, from: startOfDay)
            let daysSinceMonday = (weekday + 5) % 7
            return calendar.date(byAdding: .day, value: -daysSinceMonday, to: startOfDay)
        case "monthly":
            let components = calendar.dateComponents([.year, .month], from: startOfDay)
            return calendar.date(from: components)
        default:
            return nil
        }
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
