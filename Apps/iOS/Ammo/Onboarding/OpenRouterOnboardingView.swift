import SwiftUI
import UsageKit

/// Least-privilege OpenRouter onboarding. Until Ammo's localhost callback has
/// been verified on a physical iPhone, v1 imports an ordinary inference key
/// and marks it non-refreshable instead of assuming OAuth callback behavior.
struct OpenRouterOnboardingView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var apiKey = ""
    @State private var failure: UsageFailureKind?

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("OpenRouter", text: $label)
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

                if let failure {
                    Section {
                        SignInIssueNotice(providerName: "OpenRouter", failure: failure)
                    }
                }

                Section {
                    Button("Add Account") { importKey() }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Add OpenRouter")
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
        do {
            let tokens = try OpenRouterProvider.importedTokens(from: apiKey)
            try store.add(
                provider: .openRouter,
                label: label,
                tokens: tokens,
                imported: true)
            dismiss()
        } catch {
            AmmoLog.refresh.error("OpenRouter key import failed: \(String(describing: error), privacy: .private)")
            failure = UsageFailureClassifier.classify(error)
        }
    }
}
