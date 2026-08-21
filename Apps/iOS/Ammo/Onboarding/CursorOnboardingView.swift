import SwiftUI
import UsageKit

/// Cursor's browser approval flow gives this device its own refreshable token
/// pair. No desktop cookie or Cursor.app credential is imported.
struct CursorOnboardingView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var failure: UsageFailureKind?
    @State private var busy = false
    @State private var authFlow = CursorAuthFlow()

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("Cursor", text: $label)
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

                if let failure {
                    Section {
                        SignInIssueNotice(providerName: "Cursor", failure: failure)
                    }
                }
            }
            .navigationTitle("Add Cursor")
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
        Task {
            do {
                let tokens = try await authFlow.signIn()
                try store.add(provider: .cursor, label: label, tokens: tokens, imported: false)
                dismiss()
            } catch is CursorAuthFlow.CancelledError {
                busy = false
            } catch is CancellationError {
                busy = false
            } catch {
                AmmoLog.refresh.error("Cursor onboarding failed: \(String(describing: error), privacy: .private)")
                failure = UsageFailureClassifier.classify(error)
                busy = false
            }
        }
    }
}
