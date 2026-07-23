import Foundation

enum CodexExternalAction: Equatable {
    case updateWorkspaceBalance
    case viewUsage
}

enum CodexWorkspaceBillingAvailability: Equatable {
    case checking
    case allowed
    case restricted
    case unknown

    var permitsWorkspaceBilling: Bool {
        self == .allowed
    }
}

enum CodexWorkspaceBillingPolicy {
    static let workspaceBillingURL = URL(string: "https://chatgpt.com/admin/billing")!
    static let usageURL = URL(string: "https://chatgpt.com/codex/settings/usage")!

    /// External purchase calls to action don't require an entitlement in the
    /// United States storefront. Ammo has no external-purchase entitlement for
    /// other storefronts, so non-US and unresolved storefronts fail closed.
    static func availability(
        storefrontCountryCode: String?
    ) -> CodexWorkspaceBillingAvailability {
        guard let code = storefrontCountryCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
            !code.isEmpty
        else { return .unknown }
        return code == "USA" ? .allowed : .restricted
    }

    static func destination(
        for action: CodexExternalAction,
        storefrontCountryCode: String?
    ) -> URL? {
        switch action {
        case .viewUsage:
            usageURL
        case .updateWorkspaceBalance:
            availability(storefrontCountryCode: storefrontCountryCode).permitsWorkspaceBilling
                ? workspaceBillingURL
                : nil
        }
    }
}
