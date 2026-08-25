import Foundation
import Testing

@Suite struct PrivacyManifestTests {
    private static let manifestPaths = [
        "Apps/iOS/Ammo/PrivacyInfo.xcprivacy",
        "Apps/iOS/AmmoWidgets/PrivacyInfo.xcprivacy",
    ]

    @Test func shippingTargetsDeclareSameAppGroupUserDefaultsReason() throws {
        for path in Self.manifestPaths {
            let declarations = try declarations(in: path)
            let userDefaults = try #require(declarations.first {
                $0["NSPrivacyAccessedAPIType"] as? String
                    == "NSPrivacyAccessedAPICategoryUserDefaults"
            }, "Missing UserDefaults declaration in \(path)")
            let reasons = try #require(
                userDefaults["NSPrivacyAccessedAPITypeReasons"] as? [String])

            #expect(reasons == ["1C8F.1"], "Unexpected UserDefaults reasons in \(path)")
            #expect(!reasons.contains("CA92.1"), "Simulator-only standard defaults need no CA92.1")
        }
    }

    @Test func regressionCoversEveryShippingPrivacyManifest() throws {
        let privacyDirectory = Self.packageRoot.appendingPathComponent("Apps/iOS")
        let discovered = try FileManager.default
            .subpathsOfDirectory(atPath: privacyDirectory.path)
            .filter { $0.hasSuffix("PrivacyInfo.xcprivacy") }
            .map { "Apps/iOS/\($0)" }
            .sorted()

        #expect(discovered == Self.manifestPaths.sorted())
    }

    private func declarations(in path: String) throws -> [[String: Any]] {
        let data = try Data(contentsOf: Self.packageRoot.appendingPathComponent(path))
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        return try #require(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
    }

    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
