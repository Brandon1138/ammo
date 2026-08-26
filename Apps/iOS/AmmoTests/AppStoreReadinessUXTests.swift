import Foundation
import Testing
import UsageKit

@testable import Ammo

@Suite("App Store readiness disclosures")
struct AppStoreReadinessUXTests {
    @Test("Sign In Again says the account identity and local attachments survive")
    func reconnectCopyPreservesIdentity() {
        let account = StoredAccount(provider: .codex, label: "Work Codex")
        let copy = SignInCopy.reconnectFooter(account)

        #expect(copy.contains("same provider account"))
        #expect(copy.contains("replaces only its credential"))
        #expect(copy.contains("local history"))
        #expect(copy.contains("widget selections stay attached"))
        #expect(copy.contains("different provider account is refused"))
    }

    @Test("Removal requires a destructive action and discloses its local-only reach")
    func removalCopyDisclosesScope() {
        let account = StoredAccount(provider: .cursor, label: "Work Cursor")
        let copy = AccountRemovalCopy.message(for: account)

        #expect(AccountRemovalCopy.action == "Remove Account")
        #expect(AccountRemovalCopy.title(for: account) == "Remove Work Cursor?")
        #expect(copy.contains("credential, cached usage, history, and widget bindings"))
        #expect(copy.contains("does not sign out of or revoke"))
        #expect(copy.contains("outside Ammo"))
    }

    @Test("An expired sign-in points at Sign In Again, not account removal")
    func authenticationFailureCopyPointsAtReauthentication() {
        let message = UsageFailureKind.authentication.refreshMessage(
            providerName: "Codex", hasCachedSnapshot: false)

        #expect(message.contains("sign in again"))
        #expect(!message.lowercased().contains("remove"))
    }

    @Test("An expired sign-in never offers a blind immediate retry")
    func authenticationNeverRetriesImmediately() {
        #expect(UsageFailureKind.authentication.canRetryImmediately == false)
    }

    @Test("The auth notice's action triggers reconnect, not retry, when reconnect is supplied")
    @MainActor
    func authenticationNoticeActionTriggersReconnect() {
        var retried = false
        var reconnected = false
        let notice = RefreshIssueNotice(
            providerName: "Codex",
            failure: .authentication,
            hasCachedSnapshot: false,
            retryState: .ready,
            retry: { retried = true },
            reconnect: { reconnected = true })

        #expect(notice.actionTitle(for: .ready) == "Sign In Again")
        notice.action(for: .ready)?()

        #expect(reconnected == true)
        #expect(retried == false)
    }

    @Test("The auth notice offers no action where reconnect can't be presented, e.g. widgets")
    @MainActor
    func authenticationNoticeHasNoActionWithoutReconnect() {
        let notice = RefreshIssueNotice(
            providerName: "Codex",
            failure: .authentication,
            hasCachedSnapshot: false,
            retryState: .ready,
            retry: { Issue.record("retry should not be offered for authentication failures") })

        #expect(notice.actionTitle(for: .ready) == nil)
        #expect(notice.action(for: .ready) == nil)
    }

    @Test("Settings exposes local storage, provider processing, independence, and HTTPS help")
    func settingsPrivacyDisclosureIsComplete() {
        #expect(AmmoPrivacyDisclosure.localData.contains("iOS Keychain"))
        #expect(AmmoPrivacyDisclosure.localData.contains("App Group"))
        #expect(AmmoPrivacyDisclosure.providerProcessing.contains("directly to the provider"))
        #expect(AmmoPrivacyDisclosure.providerProcessing.contains("no developer-operated server"))
        #expect(AmmoPrivacyDisclosure.nonAffiliation.hasPrefix("Ammo is an independent app."))
        for provider in ["Anthropic", "OpenAI", "Anysphere", "OpenRouter"] {
            #expect(AmmoPrivacyDisclosure.nonAffiliation.contains(provider))
        }
        #expect(AmmoPrivacyDisclosure.privacyPolicyURL.scheme == "https")
        #expect(AmmoPrivacyDisclosure.supportURL.scheme == "https")
    }

    @Test("About section credits both authors and shows the bundle version and build")
    func settingsAboutSectionIsComplete() {
        #expect(AmmoAbout.credits.contains("Brandon Aron"))
        #expect(AmmoAbout.credits.contains("George Began-Mich"))
        #expect(AmmoAbout.versionDisplay.contains("("))
        #expect(!AmmoAbout.versionDisplay.isEmpty)
    }
}
