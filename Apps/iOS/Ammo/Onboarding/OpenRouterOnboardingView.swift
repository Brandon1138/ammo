import SwiftUI
import UsageKit

/// Least-privilege OpenRouter onboarding. Until Ammo's localhost callback has
/// been verified on a physical iPhone, v1 imports an ordinary inference key
/// and marks it non-refreshable instead of assuming OAuth callback behavior.
struct OpenRouterOnboardingView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Set when this is the existing account's "Sign in again" action rather
    /// than an add. Same flow, same view; only the destination differs.
    var reconnecting: StoredAccount?

    @State private var label = ""
    @State private var apiKey = ""
    @State private var failure: UsageFailureKind?
    @State private var mismatch: String?

    var body: some View {
        NavigationStack {
            Form {
                if let reconnecting {
                    Section {
                        Text(SignInCopy.reconnectFooter(reconnecting))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Label") {
                        TextField("OpenRouter", text: $label)
                    }
                }

                Section {
                    SecureField("sk-or-v1-…", text: $apiKey)
                        .font(.footnote.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .privacySensitive()

                    Link(destination: URL(string: "https://openrouter.ai/settings/keys")!) {
                        Label("Open OpenRouter API keys", systemImage: "safari")
                    }
                } header: {
                    Text("Ordinary API key")
                } footer: {
                    Text(
                        "Import an ordinary inference API key, not a Management key. Ammo stores it in Keychain and only reads its own spending state from GET /api/v1/key. Account-wide credits and analytics stay inaccessible."
                    )
                }

                if let mismatch {
                    Section {
                        SignInAccountMismatchNotice(message: mismatch)
                    }
                }

                if let failure {
                    Section {
                        SignInIssueNotice(providerName: "OpenRouter", failure: failure)
                    }
                }

                Section {
                    Button(SignInCopy.primaryAction(isReconnecting: reconnecting != nil,
                                                    isBusy: false)) { importKey() }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle(SignInCopy.navigationTitle(provider: .openRouter,
                                                        isReconnecting: reconnecting != nil))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onDisappear { apiKey = "" }
        }
    }

    private func importKey() {
        defer { apiKey = "" }
        failure = nil
        mismatch = nil
        do {
            let tokens = try OpenRouterProvider.importedTokens(from: apiKey)
            try store.completeSignIn(
                provider: .openRouter,
                label: label,
                tokens: tokens,
                imported: true,
                reconnecting: reconnecting)
            dismiss()
        } catch let error as AccountReconnection.IdentityMismatchError {
            mismatch = error.description
        } catch {
            AmmoLog.refresh.error("OpenRouter key import failed: \(String(describing: error), privacy: .private)")
            failure = UsageFailureClassifier.classify(error)
        }
    }
}
