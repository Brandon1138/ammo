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

/// Verbatim copy of the documented `GET /api/v1/key` 200 example published in
/// OpenRouter's OpenAPI document (`https://openrouter.ai/openapi.json`, path
/// `/key`, retrieved 2026-08-17). Fields Ammo does not read are kept so a
/// documented payload proves tolerated, not just the trimmed subset above.
private let openRouterDocumentedFixture = """
    {
      "data": {
        "byok_usage": 17.38,
        "byok_usage_daily": 17.38,
        "byok_usage_monthly": 17.38,
        "byok_usage_weekly": 17.38,
        "creator_user_id": "user_2dHFtVWx2n56w6HkM0000000000",
        "expires_at": "2027-12-31T23:59:59Z",
        "include_byok_in_limit": false,
        "is_free_tier": false,
        "is_management_key": false,
        "is_provisioning_key": false,
        "label": "sk-or-v1-au7...890",
        "limit": 100,
        "limit_remaining": 74.5,
        "limit_reset": "monthly",
        "rate_limit": {
          "interval": "1h",
          "note": "This field is deprecated and safe to ignore.",
          "requests": 1000
        },
        "usage": 25.5,
        "usage_daily": 25.5,
        "usage_monthly": 25.5,
        "usage_weekly": 25.5
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

    @Test("The documented full payload decodes and maps end to end")
    func documentedPayload() async throws {
        let provider = OpenRouterProvider(
            transport: OpenRouterFixtureTransport(
                data: Data(openRouterDocumentedFixture.utf8),
                status: 200,
                expectedToken: "ordinary-test-key"))
        let snapshot = try await provider.fetchUsage(
            tokens: OAuthTokens(accessToken: "ordinary-test-key"))
        let usage = try #require(snapshot.onDemand?.first)

        #expect(snapshot.provider == .openRouter)
        #expect(snapshot.windows.isEmpty)
        #expect(usage.used == 25.5)
        #expect(usage.limit == 100)
        #expect(usage.remaining == 74.5)
        #expect(usage.isUnlimited == false)
    }

    @Test("A dropped key-class flag does not fail the account")
    func missingKeyClassFlagsTolerated() throws {
        let fixture =
            openRouterDocumentedFixture
            .replacingOccurrences(of: "    \"is_management_key\": false,\n", with: "")
            .replacingOccurrences(of: "    \"is_provisioning_key\": false,\n", with: "")
        let usage = try #require(mappedSnapshot(fixture).onDemand?.first)

        #expect(!fixture.contains("is_management_key"))
        #expect(!fixture.contains("is_provisioning_key"))
        #expect(usage.used == 25.5)
        #expect(usage.remaining == 74.5)
    }

    @Test("A dropped period aggregate falls back to the lifetime total")
    func missingPeriodAggregatesFallBack() throws {
        let fixture =
            openRouterDocumentedFixture
            .replacingOccurrences(of: "    \"usage_monthly\": 25.5,\n", with: "")
            .replacingOccurrences(of: "    \"byok_usage_monthly\": 17.38,\n", with: "")
            .replacingOccurrences(of: "\"usage\": 25.5", with: "\"usage\": 31")
            .replacingOccurrences(of: "\"byok_usage\": 17.38", with: "\"byok_usage\": 4")
            .replacingOccurrences(of: "\"include_byok_in_limit\": false",
                                  with: "\"include_byok_in_limit\": true")
        let usage = try #require(mappedSnapshot(fixture).onDemand?.first)

        #expect(usage.used == 35)
    }

    @Test("Provisioning keys are rejected")
    func provisioningKeyRejected() throws {
        let fixture = openRouterDocumentedFixture.replacingOccurrences(
            of: "\"is_provisioning_key\": false",
            with: "\"is_provisioning_key\": true")
        let response = try OpenRouterProvider.decoder.decode(
            OpenRouterProvider.Response.self,
            from: Data(fixture.utf8))

        #expect(throws: UsageError.self) {
            _ = try OpenRouterProvider.snapshot(from: response, at: referenceDate)
        }
    }

    @Test("An over-spent key clamps remaining instead of failing the snapshot")
    func negativeRemainingIsClamped() throws {
        let fixture = openRouterFixture.replacingOccurrences(
            of: "\"limit_remaining\": 74.5",
            with: "\"limit_remaining\": -0.42")
        let usage = try #require(mappedSnapshot(fixture).onDemand?.first)

        #expect(usage.remaining == 0)
        #expect(usage.remainingAmount == 0)
        #expect(usage.isExhausted)
    }

    @Test("Non-finite monetary values are still rejected")
    func nonFiniteValuesRejected() {
        let response = OpenRouterProvider.Response(
            data: OpenRouterProvider.Response.KeyData(
                label: "sk-or-v1-test…only",
                limit: 100,
                limitRemaining: -.infinity,
                limitReset: "monthly",
                usage: 25.5,
                usageDaily: nil,
                usageWeekly: nil,
                usageMonthly: nil,
                byokUsage: nil,
                byokUsageDaily: nil,
                byokUsageWeekly: nil,
                byokUsageMonthly: nil,
                includeByokInLimit: nil,
                isManagementKey: nil,
                isProvisioningKey: nil))

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
