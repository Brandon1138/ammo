import Foundation
import Testing
import UsageKit
@testable import Ammo

private struct CodexBusinessFixtureTransport: HTTPTransport {
    func request(_ request: URLRequest) async throws -> (Data, Int) {
        (Data("""
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
        """.utf8), 200)
    }
}

@Suite("MIK-26 Codex workspace billing")
struct MIK26Tests {
    @Test("Business on-demand snapshot renders without a refresh issue")
    func businessOnDemandWithoutUsageWindows() async throws {
        let snapshot = try await CodexProvider(
            transport: CodexBusinessFixtureTransport()
        ).fetchUsage(tokens: OAuthTokens(accessToken: "test"))
        let state = AccountState(
            account: StoredAccount(provider: .codex, label: "Codex Business"),
            snapshot: snapshot,
            lastError: nil,
            lastFailure: nil,
            updatedAt: snapshot.fetchedAt)
        let usage = try #require(snapshot.onDemand?.first)
        let presentation = OnDemandUsagePresentation(
            usage: usage,
            referenceDate: snapshot.fetchedAt)

        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.onDemand?.isEmpty == false)
        #expect(state.activeFailure == nil)
        #expect(!presentation.primaryText.localizedCaseInsensitiveContains("unavailable"))
    }

    @Test("Workspace billing uses the exact ChatGPT admin destination")
    func workspaceBillingDestination() {
        #expect(
            CodexWorkspaceBillingPolicy.destination(
                for: .updateWorkspaceBalance,
                storefrontCountryCode: "USA")
                == URL(string: "https://chatgpt.com/admin/billing"))
    }

    @Test("Workspace billing is fail-closed outside the US or without a storefront")
    func workspaceBillingStorefrontPolicy() {
        #expect(
            CodexWorkspaceBillingPolicy.availability(storefrontCountryCode: "USA")
                == .allowed)
        #expect(
            CodexWorkspaceBillingPolicy.availability(storefrontCountryCode: "ROU")
                == .restricted)
        #expect(
            CodexWorkspaceBillingPolicy.availability(storefrontCountryCode: nil)
                == .unknown)
        #expect(
            CodexWorkspaceBillingPolicy.destination(
                for: .updateWorkspaceBalance,
                storefrontCountryCode: "ROU") == nil)
        #expect(
            CodexWorkspaceBillingPolicy.destination(
                for: .updateWorkspaceBalance,
                storefrontCountryCode: nil) == nil)
    }

    @Test("Viewing Codex usage stays separate from workspace billing")
    func usageDestination() {
        let expected = URL(string: "https://chatgpt.com/codex/settings/usage")

        #expect(
            CodexWorkspaceBillingPolicy.destination(
                for: .viewUsage,
                storefrontCountryCode: "USA") == expected)
        #expect(
            CodexWorkspaceBillingPolicy.destination(
                for: .viewUsage,
                storefrontCountryCode: "ROU") == expected)
        #expect(
            CodexWorkspaceBillingPolicy.destination(
                for: .viewUsage,
                storefrontCountryCode: nil) == expected)
    }

    @Test("An unresolved provider credit balance is presented honestly")
    func unavailableBalancePresentation() {
        let usage = OnDemandUsage(
            id: "codex-usage-credits",
            label: "Usage credits",
            kind: .creditBalance,
            scope: .organization,
            isEnabled: true,
            unit: .credits,
            currencyCode: "")
        let presentation = OnDemandUsagePresentation(
            usage: usage,
            referenceDate: Date(timeIntervalSince1970: 1_000))

        #expect(presentation.primaryText == "Balance unavailable")
        #expect(presentation.detailText == "Balance not reported to Ammo")
        #expect(presentation.statusText == "Unavailable")
        #expect(presentation.scopeText == "Organization")
        #expect(presentation.expirationText == nil)
    }

    @Test("Expiry distinguishes future and elapsed grants")
    func expiryPresentation() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let future = creditUsage(expiresAt: referenceDate.addingTimeInterval(90_000))
        let expired = creditUsage(expiresAt: referenceDate.addingTimeInterval(-1))

        #expect(
            OnDemandUsagePresentation(
                usage: future,
                referenceDate: referenceDate).expirationText
                == "Expires in 1d 1h")
        #expect(
            OnDemandUsagePresentation(
                usage: expired,
                referenceDate: referenceDate).expirationText
                == "Expired")
    }

    private func creditUsage(expiresAt: Date) -> OnDemandUsage {
        OnDemandUsage(
            id: "codex-usage-credits",
            label: "Usage credits",
            kind: .creditBalance,
            scope: .organization,
            isEnabled: true,
            unit: .credits,
            currencyCode: "",
            remaining: 100,
            expiresAt: expiresAt)
    }
}
