import Foundation
import Testing

@testable import UsageKit

private let openRouterFixture = """
    {
      "data": {
        "label": "sk-or-v1-test…only",
        "limit": 100,
        "limit_remaining": 74.5,
        "limit_reset": "monthly",
        "usage": 50,
        "usage_daily": 1.25,
        "usage_weekly": 7.5,
        "usage_monthly": 25.5,
        "byok_usage": 4,
        "byok_usage_daily": 0.25,
        "byok_usage_weekly": 1,
        "byok_usage_monthly": 2,
        "include_byok_in_limit": false,
        "is_management_key": false,
        "is_provisioning_key": false
      }
    }
    """

private struct OpenRouterFixtureTransport: HTTPTransport {
    let data: Data
    let status: Int
    var expectedToken: String?

    func request(_ request: URLRequest) async throws -> (Data, Int) {
        #expect(request.url == OpenRouterProvider.usageURL)
        if let expectedToken {
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(expectedToken)")
        }
        return (data, status)
    }
}

@Suite("OpenRouter least-privilege usage")
struct OpenRouterProviderTests {
    private let referenceDate = ISO8601DateFormatter().date(
        from: "2026-08-19T12:34:56Z")!

    @Test("Finite monthly budget preserves exact provider remaining")
    func finiteMonthlyBudget() throws {
        let snapshot = try mappedSnapshot(openRouterFixture)
        let usage = try #require(snapshot.onDemand?.first)

        #expect(snapshot.provider == .openRouter)
        #expect(snapshot.windows.isEmpty)
        #expect(usage.kind == .spendingLimit)
        #expect(usage.scope == .personal)
        #expect(usage.effectiveUnit == .currency)
        #expect(usage.dataSource == .providerUsageResponse)
        #expect(usage.currencyCode == "USD")
        #expect(usage.used == 25.5)
        #expect(usage.limit == 100)
        #expect(usage.remaining == 74.5)
        #expect(usage.remainingAmount == 74.5)
        #expect(usage.resetsAt == utcDate("2026-09-01T00:00:00Z"))
    }

    @Test("Daily and Monday-start weekly resets use UTC")
    func dailyAndWeeklyUTCResets() throws {
        let daily = try mappedSnapshot(
            openRouterFixture.replacingOccurrences(
                of: "\"limit_reset\": \"monthly\"",
                with: "\"limit_reset\": \"daily\""))
        let weekly = try mappedSnapshot(
            openRouterFixture.replacingOccurrences(
                of: "\"limit_reset\": \"monthly\"",
                with: "\"limit_reset\": \"weekly\""))

        #expect(daily.onDemand?.first?.used == 1.25)
        #expect(daily.onDemand?.first?.resetsAt == utcDate("2026-08-20T00:00:00Z"))
        #expect(weekly.onDemand?.first?.used == 7.5)
        #expect(weekly.onDemand?.first?.resetsAt == utcDate("2026-08-24T00:00:00Z"))
    }

    @Test("Unlimited key is valid amount-only data")
    func unlimitedKey() throws {
        let fixture =
            openRouterFixture
            .replacingOccurrences(of: "\"limit\": 100", with: "\"limit\": null")
            .replacingOccurrences(of: "\"limit_remaining\": 74.5", with: "\"limit_remaining\": null")
            .replacingOccurrences(of: "\"limit_reset\": \"monthly\"", with: "\"limit_reset\": null")
        let usage = try #require(mappedSnapshot(fixture).onDemand?.first)

        #expect(usage.isUnlimited)
        #expect(usage.used == 50)
        #expect(usage.limit == nil)
        #expect(usage.remaining == nil)
        #expect(usage.remainingAmount == nil)
        #expect(usage.remainingFraction == nil)
        #expect(usage.resetsAt == nil)
    }

    @Test("Missing limit_remaining derives only from period usage and limit")
    func missingRemaining() throws {
        let fixture = openRouterFixture.replacingOccurrences(
            of: "    \"limit_remaining\": 74.5,\n",
            with: "")
        let usage = try #require(mappedSnapshot(fixture).onDemand?.first)

        #expect(usage.remaining == nil)
        #expect(usage.used == 25.5)
        #expect(usage.remainingAmount == 74.5)
    }

    @Test("BYOK usage contributes only when the key says it counts")
    func byokLimitAccounting() throws {
        let fixture =
            openRouterFixture
            .replacingOccurrences(
                of: "\"include_byok_in_limit\": false",
                with: "\"include_byok_in_limit\": true"
            )
            .replacingOccurrences(
                of: "    \"limit_remaining\": 74.5,\n",
                with: "")
        let usage = try #require(mappedSnapshot(fixture).onDemand?.first)

        #expect(usage.used == 27.5)
        #expect(usage.remainingAmount == 72.5)
    }

    @Test("Zero remaining is preserved as exhausted")
    func zeroRemaining() throws {
        let fixture =
            openRouterFixture
            .replacingOccurrences(of: "\"limit_remaining\": 74.5", with: "\"limit_remaining\": 0")
            .replacingOccurrences(of: "\"usage_monthly\": 25.5", with: "\"usage_monthly\": 100")
        let usage = try #require(mappedSnapshot(fixture).onDemand?.first)

        #expect(usage.remaining == 0)
        #expect(usage.remainingAmount == 0)
        #expect(usage.isExhausted)
    }

    @Test("Malformed or incomplete response fails without echoing payload")
    func malformedResponse() async {
        let sentinel = "do-not-log-this-authenticated-payload"
        let provider = OpenRouterProvider(
            transport: OpenRouterFixtureTransport(
                data: Data("{\"data\":{\"label\":\"\(sentinel)\"}}".utf8),
                status: 200))

        do {
            _ = try await provider.fetchUsage(tokens: OAuthTokens(accessToken: "test-key"))
            Issue.record("Expected malformed response")
        } catch let error as UsageError {
            guard case .malformedResponse = error else {
                Issue.record("Expected malformedResponse, received \(error)")
                return
            }
            #expect(!error.description.contains(sentinel))
            #expect(UsageFailureClassifier.classify(error) == .invalidResponse)
        } catch {
            Issue.record("Expected UsageError, received \(error)")
        }
    }

    @Test("401 is authentication failure without retaining response body")
    func unauthorized() async {
        let sentinel = "revoked-key-private-response"
        let provider = OpenRouterProvider(
            transport: OpenRouterFixtureTransport(
                data: Data(sentinel.utf8),
                status: 401,
                expectedToken: "ordinary-test-key"))

        do {
            _ = try await provider.fetchUsage(
                tokens: OAuthTokens(accessToken: "ordinary-test-key"))
            Issue.record("Expected authentication failure")
        } catch let error as UsageError {
            guard case .notAuthenticated = error else {
                Issue.record("Expected notAuthenticated, received \(error)")
                return
            }
            #expect(!error.description.contains(sentinel))
            #expect(UsageFailureClassifier.classify(error) == .authentication)
        } catch {
            Issue.record("Expected UsageError, received \(error)")
        }
    }

    @Test("429 remains an HTTP status for shared backoff")
    func rateLimited() async {
        let provider = OpenRouterProvider(
            transport: OpenRouterFixtureTransport(
                data: Data("private-rate-limit-payload".utf8),
                status: 429))

        do {
            _ = try await provider.fetchUsage(tokens: OAuthTokens(accessToken: "test-key"))
            Issue.record("Expected rate limit")
        } catch let error as UsageError {
            guard case .http(let status, let body) = error else {
                Issue.record("Expected HTTP failure, received \(error)")
                return
            }
            #expect(status == 429)
            #expect(body == "OpenRouter throttled the usage request")
            #expect(UsageFailureClassifier.classify(error) == .rateLimited)
        } catch {
            Issue.record("Expected UsageError, received \(error)")
        }
    }

    @Test("Management keys are rejected")
    func managementKeyRejected() throws {
        let fixture = openRouterFixture.replacingOccurrences(
            of: "\"is_management_key\": false",
            with: "\"is_management_key\": true")
        let response = try OpenRouterProvider.decoder.decode(
            OpenRouterProvider.Response.self,
            from: Data(fixture.utf8))

        #expect(throws: UsageError.self) {
            _ = try OpenRouterProvider.snapshot(from: response, at: referenceDate)
        }
    }

    @Test("OpenRouter amount-only snapshot survives Codable round-trip")
    func snapshotCodableRoundTrip() throws {
        let fixture =
            openRouterFixture
            .replacingOccurrences(of: "\"limit\": 100", with: "\"limit\": null")
            .replacingOccurrences(of: "\"limit_remaining\": 74.5", with: "\"limit_remaining\": null")
            .replacingOccurrences(of: "\"limit_reset\": \"monthly\"", with: "\"limit_reset\": null")
        let snapshot = try mappedSnapshot(fixture)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(
            UsageSnapshot.self,
            from: encoder.encode(snapshot))

        #expect(decoded == snapshot)
    }

    @Test("Imported key is trimmed and never gains refresh material")
    func importedCredential() throws {
        let tokens = try OpenRouterProvider.importedTokens(from: "  sk-or-v1-test  \n")

        #expect(tokens.accessToken == "sk-or-v1-test")
        #expect(tokens.refreshToken == nil)
        #expect(tokens.expiresAt == nil)
    }

    private func mappedSnapshot(_ fixture: String) throws -> UsageSnapshot {
        let response = try OpenRouterProvider.decoder.decode(
            OpenRouterProvider.Response.self,
            from: Data(fixture.utf8))
        return try OpenRouterProvider.snapshot(from: response, at: referenceDate)
    }

    private func utcDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}
