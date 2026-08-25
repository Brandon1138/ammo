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

    @Test("Settings exposes local storage, provider processing, independence, and HTTPS help")
    func settingsPrivacyDisclosureIsComplete() {
        #expect(AmmoPrivacyDisclosure.localData.contains("iOS Keychain"))
        #expect(AmmoPrivacyDisclosure.localData.contains("App Group"))
        #expect(AmmoPrivacyDisclosure.providerProcessing.contains("directly to the provider"))
        #expect(AmmoPrivacyDisclosure.providerProcessing.contains("no developer-operated server"))
        for provider in ["Anthropic", "OpenAI", "Cursor", "OpenRouter"] {
            #expect(AmmoPrivacyDisclosure.nonAffiliation.contains(provider))
        }
        #expect(AmmoPrivacyDisclosure.privacyPolicyURL.scheme == "https")
        #expect(AmmoPrivacyDisclosure.supportURL.scheme == "https")
    }
}
