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
  "extra_usage": {"is_enabled": false, "monthly_limit": 1700, "used_credits": 140.0}
}
"""

private let codexFixture = """
{
  "user_id": "user-TESTTESTTESTTESTTESTTEST",
  "email": "test@example.com",
  "plan_type": "plus",
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
  "credits": {"has_credits": false, "unlimited": false, "balance": "0"},
  "rate_limit_reset_credits": {"available_count": 1}
}
"""

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
}

@Suite struct CodexDecodeTests {
    @Test func mapsWeeklyOnlyPlan() throws {
        let response = try CodexProvider.decoder.decode(
            CodexProvider.Response.self, from: Data(codexFixture.utf8))
        let windows = CodexProvider.windows(from: response)

        #expect(response.planType == "plus")
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
}
