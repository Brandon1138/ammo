import SwiftUI
import UsageKit

/// Codex onboarding (SPEC.md §Codex): primary path is on-device OAuth with the
/// loopback listener — the phone gets its own token pair, safe to refresh.
/// Fallback is pasting ~/.codex/auth.json, which Ammo will never refresh
/// (rotation could log the desktop CLI out).
struct CodexOnboardingView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var label = ""
    @State private var pastedJSON = ""
    @State private var failure: UsageFailureKind?
    @State private var busy = false
    @State private var authFlow = CodexAuthFlow()

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("Codex", text: $label)
                }

                Section {
                    Button {
                        signIn()
                    } label: {
                        Label(busy ? "Signing in…" : "Sign in with ChatGPT",
                              systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .disabled(busy)
                } header: {
                    Text("Recommended — Sign in on this device")
                } footer: {
                    Text("Ammo gets its own tokens, refreshed automatically. Your desktop Codex CLI is unaffected.")
                }

                Section {
                    TextEditor(text: $pastedJSON)
                        .font(.footnote.monospaced())
                        .frame(minHeight: 120)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .privacySensitive()
                    Button("Import pasted tokens") { importJSON() }
                        .disabled(busy || pastedJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Fallback — Paste from desktop")
                } footer: {
                    Text("Paste the contents of ~/.codex/auth.json (or just its \"tokens\" object). Imported tokens are never refreshed by Ammo — that could log out your desktop CLI — so you'll need to re-import when they expire.")
                }

                if let failure {
                    Section {
                        SignInIssueNotice(providerName: "Codex", failure: failure)
                    }
                }
            }
            .navigationTitle("Add Codex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onDisappear {
                pastedJSON = ""
                authFlow.cancel()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    authFlow.cancelForBackground()
                }
            }
        }
    }

    private func signIn() {
        busy = true
        failure = nil
        Task {
            do {
                let tokens = try await authFlow.signIn()
                try store.add(provider: .codex, label: label, tokens: tokens, imported: false)
                dismiss()
            } catch is CodexAuthFlow.CancelledError {
                busy = false
            } catch {
                AmmoLog.refresh.error("Codex onboarding failed: \(String(describing: error), privacy: .private)")
                failure = UsageFailureClassifier.classify(error)
                busy = false
            }
        }
    }

    private func importJSON() {
        defer { pastedJSON = "" }
        failure = nil
        do {
            let tokens = try Self.parseAuthJSON(pastedJSON)
            try store.add(provider: .codex, label: label, tokens: tokens, imported: true)
            dismiss()
        } catch {
            AmmoLog.refresh.error("Codex token import failed: \(String(describing: error), privacy: .private)")
            failure = UsageFailureClassifier.classify(error)
        }
    }

    /// Accepts either the whole auth.json or just its `tokens` object.
    static func parseAuthJSON(_ raw: String) throws -> OAuthTokens {
        struct FlatTokens: Decodable {
            let accessToken: String?
            let refreshToken: String?
            let accountId: String?
        }
        struct AuthFile: Decodable {
            let tokens: FlatTokens?
            let accessToken: String?
            let refreshToken: String?
            let accountId: String?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let file = try decoder.decode(AuthFile.self, from: Data(raw.utf8))
        guard let accessToken = file.tokens?.accessToken ?? file.accessToken else {
            throw UsageError.notAuthenticated("no access_token found in pasted JSON")
        }
        return OAuthTokens(accessToken: accessToken,
                           refreshToken: file.tokens?.refreshToken ?? file.refreshToken,
                           expiresAt: nil,
                           accountID: file.tokens?.accountId ?? file.accountId)
    }
}
