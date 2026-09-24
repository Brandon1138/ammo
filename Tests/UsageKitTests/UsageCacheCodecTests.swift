import Foundation
import Testing
@testable import UsageKit

@Suite("Usage App Group cache codec")
struct UsageCacheCodecTests {
    private let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Persisted snapshot round-trips with exact dates")
    func snapshotRoundTrip() throws {
        let snapshot = UsageSnapshot(
            provider: .claude,
            plan: "max",
            windows: [
                LimitWindow(
                    kind: .weekly,
                    label: "Weekly",
                    usedPercent: 42,
                    resetsAt: fetchedAt.addingTimeInterval(86_400)),
            ],
            fetchedAt: fetchedAt)

        let data = try UsageCacheCodec.encode(snapshot)
        let restored = try UsageCacheCodec.decode(UsageSnapshot.self, from: data)

        #expect(restored == snapshot)
        #expect(restored.fetchedAt == fetchedAt)
        #expect(restored.windows.first?.resetsAt == fetchedAt.addingTimeInterval(86_400))
    }

    @Test("Snapshot from older app build decodes without newer optional fields")
    func legacySnapshotDecode() throws {
        let json = """
        {
          "provider": "claude",
          "plan": "max",
          "windows": [{
            "kind": "weekly",
            "label": "Weekly",
            "usedPercent": 17,
            "resetsAt": "2027-01-15T09:00:00Z"
          }],
          "fetchedAt": "2027-01-14T09:00:00Z"
        }
        """

        let restored = try UsageCacheCodec.decode(
            UsageSnapshot.self,
            from: Data(json.utf8))

        #expect(restored.provider == .claude)
        #expect(restored.windows.first?.usedPercent == 17)
        #expect(restored.onDemand == nil)
        #expect(restored.isFreeTier == nil)
        #expect(restored.bankedResets == nil)
    }

    @Test("Legacy Codex reset credits synthesize banked resets")
    func legacyBankedResetsDecode() throws {
        let json = """
        {"provider":"codex","plan":"plus","windows":[],
         "resetCreditsAvailable":3,"fetchedAt":"2027-01-14T09:00:00Z"}
        """
        let snapshot = try UsageCacheCodec.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.bankedResets == BankedResets(count: 3))
        #expect(snapshot.resetCreditsAvailable == 3)
        #expect(try UsageCacheCodec.decode(UsageSnapshot.self,
            from: UsageCacheCodec.encode(snapshot)) == snapshot)
    }

    @Test("Legacy zero reset credits remain known and encoder keeps rollback key")
    func legacyZeroBankedResetsDecode() throws {
        let json = """
        {"provider":"codex","plan":"plus","windows":[],
         "resetCreditsAvailable":0,"fetchedAt":"2027-01-14T09:00:00Z"}
        """
        let snapshot = try UsageCacheCodec.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.bankedResets == BankedResets(count: 0))
        let encoded = try UsageCacheCodec.encode(snapshot)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["resetCreditsAvailable"] as? Int == 0)
        #expect(try UsageCacheCodec.decode(UsageSnapshot.self, from: encoded) == snapshot)
    }
}
