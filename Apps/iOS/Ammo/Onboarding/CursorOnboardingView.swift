import SwiftUI
import UsageKit

/// Cursor's browser approval flow gives this device its own refreshable token
/// pair. No desktop cookie or Cursor.app credential is imported.
struct CursorOnboardingView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Set when this is the existing account's "Sign in again" action rather
    /// than an add. Same flow, same view; only the destination differs.
    var reconnecting: StoredAccount?

    @State private var label = ""
    @State private var failure: UsageFailureKind?
    @State private var mismatch: String?
    @State private var busy = false
    @State private var authFlow = CursorAuthFlow()

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
                        TextField("Cursor", text: $label)
                    }
                }

                Section {
                    Button {
                        signIn()
                    } label: {
                        Label(busy ? "Signing in…" : "Sign in with Cursor",
                              systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .disabled(busy)
                } header: {
                    Text("Sign in on this device")
                } footer: {
                    Text("Ammo reads your included Cursor Models and Other Models usage plus any personal, team, or shared on-demand budgets Cursor reports.")
                }

                if let mismatch {
                    Section {
                        SignInAccountMismatchNotice(message: mismatch)
                    }
                }

                if let failure {
                    Section {
                        SignInIssueNotice(providerName: "Cursor", failure: failure)
                    }
                }
            }
            .navigationTitle(SignInCopy.navigationTitle(provider: .cursor,
                                                        isReconnecting: reconnecting != nil))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func signIn() {
        busy = true
        failure = nil
        mismatch = nil
        Task {
            do {
                let tokens = try await authFlow.signIn()
                try store.completeSignIn(provider: .cursor,
                                         label: label,
                                         tokens: tokens,
                                         imported: false,
                                         reconnecting: reconnecting)
                dismiss()
            } catch is CursorAuthFlow.CancelledError {
                busy = false
            } catch is CancellationError {
                busy = false
            } catch let error as AccountReconnection.IdentityMismatchError {
                mismatch = error.description
                busy = false
            } catch {
                AmmoLog.refresh.error("Cursor onboarding failed: \(String(describing: error), privacy: .private)")
                failure = UsageFailureClassifier.classify(error)
                busy = false
            }
        }
    }
}
