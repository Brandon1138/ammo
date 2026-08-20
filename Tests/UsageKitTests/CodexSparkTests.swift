import Foundation
import Testing
@testable import UsageKit

// Shape captured live from `GET https://chatgpt.com/backend-api/wham/usage`
// (2026-08-20, redacted): Spark rides in `additional_rate_limits` as one bucket
// carrying its own primary/secondary windows.
private func codexPayload(additionalRateLimits: String) -> Data {
    Data("""
    {
      "plan_type": "prolite",
      "rate_limit": {
        "allowed": false,
        "limit_reached": true,
        "primary_window": {
          "used_percent": 100,
          "limit_window_seconds": 604800,
          "reset_after_seconds": 420888,
          "reset_at": 1787657830
        },
        "secondary_window": null
      },
      "additional_rate_limits": \(additionalRateLimits),
      "credits": {"has_credits": false, "unlimited": false, "balance": "0",
                  "overage_limit_reached": false},
      "spend_control": {"individual_limit": null},
      "rate_limit_reset_credits": {"available_count": 0}
    }
    """.utf8)
}

private let sparkBucket = """
    [
      {
        "limit_name": "GPT-5.3-Codex-Spark",
        "metered_feature": "codex_bengalfox",
        "rate_limit": {
          "allowed": true,
          "limit_reached": false,
          "primary_window": {
            "used_percent": 12,
            "limit_window_seconds": 18000,
            "reset_after_seconds": 18000,
            "reset_at": 1787254942
          },
          "secondary_window": {
            "used_percent": 34,
            "limit_window_seconds": 604800,
            "reset_after_seconds": 604800,
            "reset_at": 1787841742
          }
        }
      }
    ]
    """

/// Same bucket with the two windows swapped between the payload slots.
private let sparkBucketReversed = """
    [
      {
        "limit_name": "GPT-5.3-Codex-Spark",
        "metered_feature": "codex_bengalfox",
        "rate_limit": {
          "primary_window": {
            "used_percent": 34,
            "limit_window_seconds": 604800,
            "reset_at": 1787841742
          },
          "secondary_window": {
            "used_percent": 12,
            "limit_window_seconds": 18000,
            "reset_at": 1787254942
          }
        }
      }
    ]
    """

private func windows(_ additionalRateLimits: String) throws -> [LimitWindow] {
    let response = try CodexProvider.decoder.decode(
        CodexProvider.Response.self, from: codexPayload(additionalRateLimits: additionalRateLimits))
    return CodexProvider.windows(from: response)
}

@Suite struct CodexSparkTests {
    @Test func addsTwoModelScopedWindowsForSpark() throws {
        let parsed = try windows(sparkBucket)

        #expect(parsed.count == 3)
        #expect(parsed[0].kind == .weekly)
        #expect(parsed[0].label == "Weekly")

        #expect(parsed[1].kind == .modelScoped)
        #expect(parsed[1].label == "Spark")
        #expect(parsed[1].usedPercent == 12)
        #expect(parsed[1].resetsAt == Date(timeIntervalSince1970: 1_787_254_942))

        #expect(parsed[2].kind == .modelScoped)
        #expect(parsed[2].label == "Spark weekly")
        #expect(parsed[2].usedPercent == 34)
        #expect(parsed[2].resetsAt == Date(timeIntervalSince1970: 1_787_841_742))
    }

    @Test func sparkWindowIDsStayUnique() throws {
        let parsed = try windows(sparkBucket)
        #expect(Set(parsed.map(\.id)).count == parsed.count)
    }

    @Test func labelsSparkWindowsByDurationNotPosition() throws {
        #expect(try windows(sparkBucketReversed).map(\.label)
            == ["Weekly", "Spark", "Spark weekly"])
        // Ordering and labeling are identical whichever slot each window landed in.
        #expect(try windows(sparkBucketReversed).map(\.usedPercent)
            == windows(sparkBucket).map(\.usedPercent))
    }

    @Test func classifiesSparkLabelsByAdvertisedLength() {
        #expect(CodexProvider.sparkLabel(windowSeconds: 18000) == "Spark")
        #expect(CodexProvider.sparkLabel(windowSeconds: 604800) == "Spark weekly")
        #expect(CodexProvider.sparkLabel(windowSeconds: 2_592_000) == "Spark monthly")
        #expect(CodexProvider.sparkLabel(windowSeconds: nil) == "Spark")
    }

    @Test func absentSparkBucketAddsNothing() throws {
        #expect(try windows("null").map(\.label) == ["Weekly"])
        #expect(try windows("[]").map(\.label) == ["Weekly"])
    }

    @Test func unrecognizedBucketIsIgnored() throws {
        let other = """
            [
              {
                "limit_name": "Some-Other-Model",
                "metered_feature": "codex_unrelated",
                "rate_limit": {
                  "primary_window": {"used_percent": 9, "limit_window_seconds": 18000}
                }
              }
            ]
            """
        #expect(try windows(other).map(\.label) == ["Weekly"])
    }

    @Test func malformedBucketDegradesToAbsence() throws {
        // Wrong types at every level: the bucket, its rate limit, and the array.
        #expect(try windows("""
            [{"limit_name": 7, "metered_feature": false, "rate_limit": "nope"}]
            """).map(\.label) == ["Weekly"])
        #expect(try windows("""
            [{"limit_name": "GPT-5.3-Codex-Spark", "rate_limit": {"primary_window": []}}]
            """).map(\.label) == ["Weekly"])
        #expect(try windows("\"not-an-array\"").map(\.label) == ["Weekly"])
        #expect(try windows("{\"limit_name\": \"GPT-5.3-Codex-Spark\"}").map(\.label) == ["Weekly"])
    }

    @Test func sparkWindowWithoutPercentIsSkipped() throws {
        let partial = """
            [
              {
                "limit_name": "GPT-5.3-Codex-Spark",
                "rate_limit": {
                  "primary_window": {"limit_window_seconds": 18000, "reset_at": 1787254942},
                  "secondary_window": {"used_percent": 34, "limit_window_seconds": 604800}
                }
              }
            ]
            """
        #expect(try windows(partial).map(\.label) == ["Weekly", "Spark weekly"])
    }

    @Test func matchesSparkByMeteredFeatureWhenNameChanges() throws {
        let renamed = """
            [
              {
                "limit_name": "GPT-6-Codex-Something-Else",
                "metered_feature": "codex_bengalfox",
                "rate_limit": {
                  "primary_window": {"used_percent": 3, "limit_window_seconds": 18000}
                }
              }
            ]
            """
        #expect(try windows(renamed).map(\.label) == ["Weekly", "Spark"])
    }
}
