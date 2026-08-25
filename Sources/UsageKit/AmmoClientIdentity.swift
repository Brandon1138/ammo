import Foundation

/// Ammo's HTTP client identity, derived from app metadata without depending on UIKit.
public struct AmmoClientIdentity: Equatable, Sendable {
    public let version: String?
    public let build: String?

    public init(version: String?, build: String?) {
        self.version = Self.nonEmpty(version)
        self.build = Self.nonEmpty(build)
    }

    public static var current: Self {
        derived(from: Bundle.main.infoDictionary)
    }

    public var userAgent: String {
        let product = version.map { "Ammo/\($0)" } ?? "Ammo"
        return build.map { "\(product) (build \($0))" } ?? product
    }

    static func derived(from infoDictionary: [String: Any]?) -> Self {
        Self(
            version: infoDictionary?["CFBundleShortVersionString"] as? String,
            build: infoDictionary?["CFBundleVersion"] as? String
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}
