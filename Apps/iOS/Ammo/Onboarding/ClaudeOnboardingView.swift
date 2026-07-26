import SwiftUI
import UsageKit

/// Claude paste-code onboarding (SPEC.md §Claude): open the code=true authorize
/// URL, the user signs in and copies the code the page displays, pastes it here.
/// The phone gets its own token pair — no interaction with any CLI login.
struct ClaudeOnboardingView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var pkce = PKCE()
    @State private var label = ""
    @State private var code = ""
    @State private var showingWeb = false
    @State private var failure: UsageFailureKind?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Sign in to Claude and approve access. The final page displays an authorization code — copy it, come back, and paste it below.")
                        .font(.callout)
                    Button {
                        showingWeb = true
                    } label: {
                        Label("Open Claude sign-in", systemImage: "safari")
                    }
                } header: {
                    Text("Step 1 — Sign in")
                }

                Section("Step 2 — Paste the code") {
                    TextField("Authorization code", text: $code, axis: .vertical)
                        .font(.footnote.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Label") {
                    TextField("Claude", text: $label)
                }

                if let failure {
                    Section {
                        SignInIssueNotice(providerName: "Claude", failure: failure)
                    }
                }

                Section {
                    Button(busy ? "Adding…" : "Add Account") { submit() }
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }
            }
            .navigationTitle("Add Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingWeb) {
                SafariView(url: ClaudeProvider.authorizationRequestURL(pkce: pkce))
                    .ignoresSafeArea()
            }
        }
    }

    private func submit() {
        busy = true
        failure = nil
        Task {
            do {
                let tokens = try await ClaudeProvider()
                    .exchangeCode(code, verifier: pkce.verifier, state: pkce.state)
                try store.add(provider: .claude, label: label, tokens: tokens, imported: false)
                dismiss()
            } catch {
                AmmoLog.refresh.error("Claude onboarding failed: \(String(describing: error), privacy: .private)")
                failure = UsageFailureClassifier.classify(error)
                busy = false
            }
        }
    }
}
