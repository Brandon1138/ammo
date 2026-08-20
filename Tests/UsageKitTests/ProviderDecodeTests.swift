import Foundation
import Testing
@testable import UsageKit

// Fixtures are scrubbed captures of live responses (2026-07-16). If a decode test
// starts failing after a provider change, re-capture per SPEC.md "Re-deriving the
// contracts" and update both the fixture and the spec.

private let claudeFixture = """
{
  "five_hour": {"utilization": 36.0, "resets_at": "2026-07-16T15:19:59.837992+00:00"},
  "seven_day": {"utilization": 4.0, "resets_at": "2026-07-17T17:59:59.838014+00:00"},
  "seven_day_opus": null,
  "limits": [
    {"kind": "session", "group": "session", "percent": 36, "severity": "normal",
     "resets_at": "2026-07-16T15:19:59.837992+00:00", "scope": null, "is_active": true},
    {"kind": "weekly_all", "group": "weekly", "percent": 4, "severity": "normal",
     "resets_at": "2026-07-17T17:59:59.838014+00:00", "scope": null, "is_active": false},
    {"kind": "weekly_scoped", "group": "weekly", "percent": 7, "severity": "normal",
     "resets_at": "2026-07-17T17:59:59.838327+00:00",
     "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false}
  ],
  "extra_usage": {"is_enabled": false, "monthly_limit": 1700, "used_credits": 140.0,
                  "utilization": 8.235, "currency": "EUR"}
}
"""

private let claudeProfileFixture = """
{
  "account": {"uuid": "account-test", "email_address": "test@example.com"},
  "organization": {
    "uuid": "organization-test",
    "organization_type": "claude_max",
    "rate_limit_tier": "default_claude_max_20x",
    "seat_tier": null
  }
}
"""

private let codexFixture = """
{
  "user_id": "user-TESTTESTTESTTESTTESTTEST",
  "email": "test@example.com",
  "plan_type": "self_serve_business_usage_based",
  "rate_limit": {
    "allowed": true,
    "limit_reached": false,
    "primary_window": {
      "used_percent": 5,
      "limit_window_seconds": 604800,
      "reset_after_seconds": 590909,
      "reset_at": 1784797038
    },
    "secondary_window": null
  },
  "additional_rate_limits": null,
  "credits": {
    "has_credits": true,
    "unlimited": false,
    "balance": null,
    "overage_limit_reached": false
  },
  "spend_control": {
    "individual_limit": {
      "limit": "100", "used": 37.5, "remaining_percent": "62.5", "resets_at": "1784797038"
    }
  },
  "rate_limit_reset_credits": {"available_count": 1}
}
"""

private let cursorFixture = """
{
  "billingCycleStart": "2026-07-10T00:00:00.000Z",
  "billingCycleEnd": "2026-08-10T00:00:00.000Z",
  "membershipType": "pro",
  "individualUsage": {
    "plan": {
      "used": 20,
      "limit": 2000,
      "autoPercentUsed": 1.0,
      "apiPercentUsed": 0.0,
      "totalPercentUsed": 1.0
    },
    "onDemand": {
      "enabled": true,
      "used": 550,
      "limit": 5000,
      "remaining": 4450
    },
    "overall": {"enabled": true, "used": 7384, "limit": 10000, "remaining": 2616}
  },
  "teamUsage": {
    "onDemand": {"enabled": true, "used": 2500, "limit": 25000, "remaining": 22500},
    "pooled": {"enabled": true, "used": 120000, "limit": 500000, "remaining": 380000}
  }
}
"""

private struct FixtureTransport: HTTPTransport {
    let data: Data
    let status: Int

    func request(_ request: URLRequest) async throws -> (Data, Int) {
        (data, status)
    }
}

@Suite struct ClaudeDecodeTests {
    @Test func mapsLimitsArrayToWindows() throws {
        let response = try ClaudeProvider.decoder.decode(
            ClaudeProvider.Response.self, from: Data(claudeFixture.utf8))
        let windows = ClaudeProvider.windows(from: response)

        #expect(windows.count == 3)
        #expect(windows[0] == LimitWindow(kind: .session, label: "Session", usedPercent: 36,
                                          resetsAt: windows[0].resetsAt))
        #expect(windows[0].resetsAt != nil)
        #expect(windows[1].kind == .weekly)
        #expect(windows[1].usedPercent == 4)
        #expect(windows[2].kind == .modelScoped)
        #expect(windows[2].label == "Fable")
        #expect(windows[2].usedPercent == 7)
        #expect(windows[2].remainingPercent == 93)
    }

    @Test func fallsBackToBucketsWhenLimitsMissing() throws {
        let stripped = claudeFixture.replacingOccurrences(of: "\"limits\"", with: "\"limits_gone\"")
        let response = try ClaudeProvider.decoder.decode(
            ClaudeProvider.Response.self, from: Data(stripped.utf8))
        let windows = ClaudeProvider.windows(from: response)

        #expect(windows.count == 2)
        #expect(windows[0].kind == .session)
        #expect(windows[0].usedPercent == 36)
        #expect(windows[1].kind == .weekly)
    }

    @Test func parsesSixDigitFractionalTimestamps() {
        let date = ISO8601.parse("2026-07-16T15:19:59.837992+00:00")
        #expect(date != nil)
    }

    @Test func mapsExtraUsageMinorUnitsAndDisabledState() throws {
        let response = try ClaudeProvider.decoder.decode(
            ClaudeProvider.Response.self, from: Data(claudeFixture.utf8))
        let extra = try #require(ClaudeProvider.onDemand(from: response)?.first)

        #expect(extra.id == "claude-extra-usage")
        #expect(extra.isEnabled == false)
        #expect(extra.currencyCode == "EUR")
        #expect(extra.used == 1.4)
        #expect(extra.limit == 17)
        #expect(extra.remainingAmount == 15.6)
        #expect(extra.usedPercent == 8.235)
    }

    @Test func mapsOAuthProfileToPlanBadge() throws {
        let profile = try #require(ClaudeProvider.profile(from: Data(claudeProfileFixture.utf8)))
        #expect(ClaudeProvider.plan(from: profile) == "max")
    }

    @Test func prefersSubscriptionTypeAndIgnoresGenericTiers() throws {
        let data = Data("""
        {"subscription_type":"pro","rate_limit_tier":"default_claude_ai"}
        """.utf8)
        let profile = try #require(ClaudeProvider.profile(from: data))
        #expect(ClaudeProvider.plan(from: profile) == "pro")
    }
}

@Suite struct CodexDecodeTests {
    @Test func mapsWeeklyOnlyPlan() throws {
        let response = try CodexProvider.decoder.decode(
            CodexProvider.Response.self, from: Data(codexFixture.utf8))
        let windows = CodexProvider.windows(from: response)

        #expect(response.planType == "self_serve_business_usage_based")
        #expect(response.rateLimitResetCredits?.availableCount == 1)
        #expect(windows.count == 1)
        #expect(windows[0].kind == .weekly)
        #expect(windows[0].label == "Weekly")
        #expect(windows[0].usedPercent == 5)
        #expect(windows[0].resetsAt == Date(timeIntervalSince1970: 1_784_797_038))
    }

    @Test func classifiesWindowsByLengthNotPosition() {
        #expect(CodexProvider.classify(windowSeconds: 18000) == (.session, "Session"))
        #expect(CodexProvider.classify(windowSeconds: 604800) == (.weekly, "Weekly"))
        #expect(CodexProvider.classify(windowSeconds: 2_592_000) == (.monthly, "Monthly"))
        #expect(CodexProvider.classify(windowSeconds: nil) == (.unknown, "Usage"))
    }

    @Test func fetchAcceptsBusinessOnDemandWithoutUsageWindows() async throws {
        let fixture = """
        {
          "plan_type": "self_serve_business_usage_based",
          "rate_limit": null,
          "credits": {
            "has_credits": true,
            "unlimited": false,
            "balance": "9112.25",
            "overage_limit_reached": false
          }
        }
        """
        let provider = CodexProvider(
            transport: FixtureTransport(data: Data(fixture.utf8), status: 200))

        let snapshot = try await provider.fetchUsage(
            tokens: OAuthTokens(accessToken: "test"))

        #expect(snapshot.displayPlan == "Business")
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.onDemand?.count == 1)
        #expect(snapshot.onDemand?.first?.remainingAmount == 9_112.25)
    }

    @Test func fetchRejectsResponseWithoutIncludedOrOnDemandUsage() async {
        let provider = CodexProvider(
            transport: FixtureTransport(
                data: Data(#"{"plan_type":"plus","rate_limit":null}"#.utf8),
                status: 200))

        do {
            _ = try await provider.fetchUsage(tokens: OAuthTokens(accessToken: "test"))
            Issue.record("Expected an explicit malformed-response failure")
        } catch let error as UsageError {
            guard case .malformedResponse = error else {
                Issue.record("Expected malformedResponse, received \(error)")
                return
            }
        } catch {
            Issue.record("Expected UsageError, received \(error)")
        }
    }

    @Test func keepsPurchasedCreditsSeparateFromResetTokensAndSpendControls() throws {
        let response = try CodexProvider.decoder.decode(
            CodexProvider.Response.self, from: Data(codexFixture.utf8))
        let entries = try #require(CodexProvider.onDemand(from: response))

        #expect(entries.count == 2)
        #expect(entries[0].id == "codex-usage-credits")
        #expect(entries[0].remainingAmount == nil)
        #expect(entries[0].kind == .creditBalance)
        #expect(entries[0].scope == .organization)
        #expect(entries[0].effectiveUnit == .credits)
        #expect(entries[0].isExhausted == false)
        #expect(entries[1].id == "codex-individual-limit")
        #expect(entries[1].used == 37.5)
        #expect(entries[1].limit == 100)
        #expect(entries[1].remainingAmount == 62.5)
        #expect(entries[1].resetsAt == Date(timeIntervalSince1970: 1_784_797_038))
        #expect(response.rateLimitResetCredits?.availableCount == 1)
    }

    @Test func mapsBusinessPlanToReadableBadge() throws {
        let response = try CodexProvider.decoder.decode(
            CodexProvider.Response.self, from: Data(codexFixture.utf8))
        let snapshot = UsageSnapshot(
            provider: .codex,
            plan: response.planType,
            windows: [])

        #expect(snapshot.displayPlan == "Business")
    }

    @Test func mapsBothPaidIndividualCodexTiersToPro() {
        // "prolite" is ChatGPT's internal name for the 5x tier; nobody
        // subscribes under it, so both individual tiers read as Pro.
        #expect(UsageSnapshot(provider: .codex, plan: "prolite", windows: []).displayPlan == "Pro")
        #expect(UsageSnapshot(provider: .codex, plan: "pro", windows: []).displayPlan == "Pro")
        #expect(UsageSnapshot(provider: .codex, plan: "plus", windows: []).displayPlan == "Plus")
    }

    @Test func preservesExactBalanceOnlyFromProviderUsageResponse() throws {
        let fixture = codexFixture.replacingOccurrences(
            of: "\"balance\": null",
            with: "\"balance\": \"9112.25\"")
        let response = try CodexProvider.decoder.decode(
            CodexProvider.Response.self, from: Data(fixture.utf8))
        let usage = try #require(CodexProvider.onDemand(from: response)?.first)
        let snapshot = UsageSnapshot(
            provider: .codex,
            plan: response.planType,
            windows: [],
            onDemand: [usage])
        let sanitized = CodexProvider.removingUnverifiedBillingData(from: snapshot)
        let preserved = try #require(sanitized.onDemand?.first)

        #expect(preserved.dataSource == .providerUsageResponse)
        #expect(preserved.remainingAmount == 9_112.25)
        #expect(preserved.expiresAt == nil)
    }

    @Test func removesLegacyPrivateBillingValuesFromDisplaySnapshot() throws {
        let legacyCapture = OnDemandUsage(
            id: "codex-usage-credits",
            label: "Usage credits",
            kind: .creditBalance,
            scope: .organization,
            isEnabled: true,
            unit: .credits,
            dataSource: nil,
            currencyCode: "",
            remaining: 9_112,
            expiresAt: ISO8601.parse("2026-07-29T20:59:00Z"),
            equivalentAmount: 1_500,
            equivalentCurrencyCode: "RON")
        let snapshot = UsageSnapshot(
            provider: .codex,
            plan: "self_serve_business_usage_based",
            windows: [],
            onDemand: [legacyCapture])
        let usage = try #require(
            CodexProvider.removingUnverifiedBillingData(from: snapshot).onDemand?.first)

        #expect(usage.dataSource == nil)
        #expect(usage.isEnabled == true)
        #expect(usage.remainingAmount == nil)
        #expect(usage.expiresAt == nil)
        #expect(usage.equivalentAmount == nil)
        #expect(usage.equivalentCurrencyCode == nil)
    }
}

@Suite struct CursorDecodeTests {
    @Test func mapsOnlyIncludedComposerAndAPIUsage() throws {
        let response = try CursorProvider.decoder.decode(
            CursorProvider.Response.self, from: Data(cursorFixture.utf8))
        let windows = CursorProvider.windows(from: response)

        #expect(response.membershipType == "pro")
        #expect(windows.count == 2)
        #expect(windows[0].kind == .monthly)
        #expect(windows[0].label == "Composer")
        #expect(windows[0].usedPercent == 1)
        #expect(windows[1].kind == .monthly)
        #expect(windows[1].label == "API")
        #expect(windows[1].usedPercent == 0)
        #expect(windows[0].resetsAt == windows[1].resetsAt)
        #expect(windows[0].resetsAt == ISO8601.parse("2026-08-10T00:00:00.000Z"))
    }

    @Test func acceptsRenamedFirstPartyPercentageAndClampsValues() throws {
        let fixture = """
        {
          "billingCycleEnd": "2026-08-10T00:00:00Z",
          "membershipType": "pro",
          "individualUsage": {
            "plan": {"firstPartyPercentUsed": 101, "apiPercentUsed": -1}
          }
        }
        """
        let response = try CursorProvider.decoder.decode(
            CursorProvider.Response.self, from: Data(fixture.utf8))
        let windows = CursorProvider.windows(from: response)

        #expect(windows.map(\.usedPercent) == [100, 0])
    }

    @Test func fetchAcceptsOneAvailableIncludedWindow() async throws {
        let fixture = """
        {
          "billingCycleEnd": "2026-08-10T00:00:00Z",
          "membershipType": "pro",
          "individualUsage": {
            "plan": {"firstPartyPercentUsed": 25}
          }
        }
        """
        let provider = CursorProvider(
            transport: FixtureTransport(data: Data(fixture.utf8), status: 200))

        let snapshot = try await provider.fetchUsage(tokens: OAuthTokens(
            accessToken: "test",
            accountID: "user-test"))

        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows.first?.label == "Composer")
        #expect(snapshot.windows.first?.usedPercent == 25)
    }

    @Test func fetchRejectsResponseWithoutIncludedOrOnDemandUsage() async {
        let provider = CursorProvider(
            transport: FixtureTransport(
                data: Data(#"{"membershipType":"pro","individualUsage":{"plan":{}}}"#.utf8),
                status: 200))

        do {
            _ = try await provider.fetchUsage(tokens: OAuthTokens(
                accessToken: "test",
                accountID: "user-test"))
            Issue.record("Expected an explicit malformed-response failure")
        } catch let error as UsageError {
            guard case .malformedResponse = error else {
                Issue.record("Expected malformedResponse, received \(error)")
                return
            }
        } catch {
            Issue.record("Expected UsageError, received \(error)")
        }
    }

    @Test func fetchPreservesOnDemandOnlyResponse() async throws {
        let fixture = """
        {
          "membershipType": "team",
          "individualUsage": {
            "plan": {},
            "onDemand": {"enabled": true, "used": 550, "limit": 5000, "remaining": 4450}
          }
        }
        """
        let provider = CursorProvider(
            transport: FixtureTransport(data: Data(fixture.utf8), status: 200))

        let snapshot = try await provider.fetchUsage(tokens: OAuthTokens(
            accessToken: "test",
            accountID: "user-test"))

        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.onDemand?.first?.remainingAmount == 44.5)
    }

    @Test func preservesPersonalTeamAndEnterpriseOnDemandPools() throws {
        let response = try CursorProvider.decoder.decode(
            CursorProvider.Response.self, from: Data(cursorFixture.utf8))
        let entries = try #require(CursorProvider.onDemand(from: response))

        #expect(entries.map(\.id) == [
            "cursor-personal-on-demand",
            "cursor-personal-allocation",
            "cursor-team-on-demand",
            "cursor-shared-pool",
        ])
        #expect(entries[0].used == 5.5)
        #expect(entries[0].limit == 50)
        #expect(entries[0].remainingAmount == 44.5)
        #expect(entries[1].remainingAmount == 26.16)
        #expect(entries[2].scope == .team)
        #expect(entries[2].limit == 250)
        #expect(entries[3].scope == .organization)
        #expect(entries[3].used == 1_200)
        #expect(entries[3].limit == 5_000)
        #expect(entries.allSatisfy { $0.resetsAt == ISO8601.parse("2026-08-10T00:00:00.000Z") })
    }

    @Test func doesNotInventUnlimitedFromMissingCursorAmounts() throws {
        let fixture = """
        {
          "membershipType": "team",
          "individualUsage": {
            "onDemand": {"enabled": true}
          }
        }
        """
        let response = try CursorProvider.decoder.decode(
            CursorProvider.Response.self, from: Data(fixture.utf8))
        let usage = try #require(CursorProvider.onDemand(from: response)?.first)

        #expect(usage.isEnabled == true)
        #expect(usage.isUnlimited == false)
        #expect(usage.remainingAmount == nil)
    }
}

@Suite struct OnDemandModelTests {
    @Test func verifiedMonetaryBalanceFailsClosedOnLegacyAndCreditValues() throws {
        let legacy = OnDemandUsage(
            id: "legacy",
            label: "Legacy balance",
            kind: .creditBalance,
            scope: .organization,
            isEnabled: true,
            unit: .currency,
            dataSource: nil,
            currencyCode: "USD",
            remaining: 999)
        let credits = OnDemandUsage(
            id: "credits",
            label: "Usage credits",
            kind: .creditBalance,
            scope: .organization,
            isEnabled: true,
            unit: .credits,
            currencyCode: "",
            remaining: 100)
        let exactMoney = OnDemandUsage(
            id: "money",
            label: "On-demand",
            kind: .spendingLimit,
            scope: .personal,
            isEnabled: true,
            unit: .currency,
            currencyCode: "USD",
            remaining: 44.5)
        let snapshot = UsageSnapshot(
            provider: .cursor,
            plan: "pro",
            windows: [],
            onDemand: [legacy, credits, exactMoney])

        let selected = try #require(snapshot.verifiedMonetaryOnDemandBalance)
        #expect(selected.id == "money")
        #expect(selected.remainingAmount == 44.5)
        #expect(selected.dataSource == .providerUsageResponse)
    }

    @Test func verifiedMonetaryBalanceOmitsDisabledOrAmountlessPools() {
        let disabled = OnDemandUsage(
            id: "disabled",
            label: "On-demand",
            kind: .spendingLimit,
            scope: .personal,
            isEnabled: false,
            currencyCode: "USD",
            remaining: 20)
        let amountless = OnDemandUsage(
            id: "amountless",
            label: "On-demand",
            kind: .spendingLimit,
            scope: .personal,
            isEnabled: true,
            currencyCode: "USD")
        let snapshot = UsageSnapshot(
            provider: .cursor,
            plan: "pro",
            windows: [],
            onDemand: [disabled, amountless])

        #expect(snapshot.verifiedMonetaryOnDemandBalance == nil)
    }
}
