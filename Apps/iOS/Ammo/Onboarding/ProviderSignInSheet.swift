import SwiftUI
import UsageKit

/// Routes to the one onboarding flow a provider already has.
///
/// Re-authentication deliberately has no flow of its own: it presents the exact
/// same view the add flow does, with `reconnecting` set. Whatever the provider's
/// sign-in produces is then written back under the existing account id.
struct ProviderSignInSheet: View {
    let provider: ProviderID
    var reconnecting: StoredAccount?

    var body: some View {
        switch provider {
        case .claude: ClaudeOnboardingView(reconnecting: reconnecting)
        case .codex: CodexOnboardingView(reconnecting: reconnecting)
        case .cursor: CursorOnboardingView(reconnecting: reconnecting)
        case .openRouter: OpenRouterOnboardingView(reconnecting: reconnecting)
        case .antigravity: EmptyView() // deferred, see SPEC.md
        }
    }
}

/// Shown when a sign-in succeeded but belongs to a different provider-side
/// account than the one being repaired. Overwriting anyway would attach this
/// account's history to someone else's usage.
struct SignInAccountMismatchNotice: View {
    let message: String

    var body: some View {
        InlineStatusNotice(title: "Different account",
                           message: message,
                           systemImage: "person.crop.circle.badge.exclamationmark")
    }
}

/// Title and primary-action copy shared by every onboarding flow, so the add
/// and re-authenticate presentations of one view never drift apart.
enum SignInCopy {
    static func navigationTitle(provider: ProviderID, isReconnecting: Bool) -> String {
        isReconnecting ? "Sign In Again" : "Add \(provider.displayName)"
    }

    static func primaryAction(isReconnecting: Bool, isBusy: Bool) -> String {
        switch (isReconnecting, isBusy) {
        case (true, true): "Signing in…"
        case (true, false): "Sign In Again"
        case (false, true): "Adding…"
        case (false, false): "Add Account"
        }
    }

    static func reconnectFooter(_ account: StoredAccount) -> String {
        """
        Signing in again replaces the credential for \(account.label) in place.         Its usage history and any widget showing it stay attached.
        """
    }
}
