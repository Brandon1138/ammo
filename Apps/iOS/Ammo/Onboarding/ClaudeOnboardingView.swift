import SwiftUI
import UsageKit

/// Claude paste-code onboarding (SPEC.md §Claude): open the code=true authorize
/// URL, the user signs in and copies the code the page displays, pastes it here.
/// The phone gets its own token pair — no interaction with any CLI login.
struct ClaudeOnboardingView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Set when this is the existing account's "Sign in again" action rather
    /// than an add. Same flow, same view; only the destination differs.
    var reconnecting: StoredAccount?

    @State private var pkce = PKCE()
    @State private var label = ""
    @State private var code = ""
    @State private var showingWeb = false
    @State private var failure: UsageFailureKind?
    @State private var mismatch: String?
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
                        .privacySensitive()
                }

                if let reconnecting {
                    Section {
                        Text(SignInCopy.reconnectFooter(reconnecting))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Label") {
                        TextField("Claude", text: $label)
                    }
                }

                if let mismatch {
                    Section {
                        SignInAccountMismatchNotice(message: mismatch)
                    }
                }

                if let failure {
                    Section {
                        SignInIssueNotice(providerName: "Claude", failure: failure)
                    }
                }

                Section {
                    Button(SignInCopy.primaryAction(isReconnecting: reconnecting != nil,
                                                    isBusy: busy)) { submit() }
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }
            }
            .navigationTitle(SignInCopy.navigationTitle(provider: .claude,
                                                        isReconnecting: reconnecting != nil))
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
            .onDisappear { code = "" }
        }
    }

    private func submit() {
        busy = true
        failure = nil
        mismatch = nil
        Task {
            defer { code = "" }
            do {
                let tokens = try await ClaudeProvider()
                    .exchangeCode(code, verifier: pkce.verifier, state: pkce.state)
                try store.completeSignIn(provider: .claude,
                                         label: label,
                                         tokens: tokens,
                                         imported: false,
                                         reconnecting: reconnecting)
                dismiss()
            } catch let error as AccountReconnection.IdentityMismatchError {
                mismatch = error.description
                busy = false
            } catch {
                AmmoLog.refresh.error("Claude onboarding failed: \(String(describing: error), privacy: .private)")
                failure = UsageFailureClassifier.classify(error)
                busy = false
            }
        }
    }
}
