import SwiftUI
import UIKit
import UsageKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AccountStore.self) private var store
    /// Owned by the sheet so presentation never waits on model preparation.
    /// Loading preferences is a synchronous UserDefaults read; the authorization
    /// status arrives from `.task` below and only gates the master toggle.
    @State private var model = NotificationSettingsModel()
    @State private var payloadExport: PayloadExport?
    @State private var payloadExportError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable notifications", isOn: masterBinding)
                        .disabled(model.authorizationStatus == nil || model.isUpdatingAuthorization)

                    if model.permissionDenied {
                        notificationPermissionNotice
                    } else if model.authorizationRequestFailed {
                        Text("Ammo couldn't request notification permission. Try again.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Notifications")
                }

                Section {
                    Toggle("Weekly reset", isOn: preferenceBinding(\.codexWeeklyReset))
                    Toggle("Spontaneous reset granted", isOn: preferenceBinding(\.codexSpontaneousReset))
                    Toggle("Banked reset granted", isOn: preferenceBinding(\.codexBankedReset))
                } header: {
                    Text("Codex")
                } footer: {
                    Text("Weekly reset alerts fire when weekly usage renews. Spontaneous and banked alerts fire when Ammo observes provider-granted resets.")
                }
                .disabled(!model.preferences.masterEnabled)

                Section {
                    Toggle("Session (5h) reset", isOn: preferenceBinding(\.claudeSessionReset))
                    Toggle("Weekly reset", isOn: preferenceBinding(\.claudeWeeklyReset))
                    Toggle("Spontaneous reset granted", isOn: preferenceBinding(\.claudeSpontaneousReset))
                } header: {
                    Text("Claude")
                } footer: {
                    Text("Session reset alerts only fire after you used that 5-hour session. Weekly and spontaneous alerts fire when Ammo observes those resets.")
                }
                .disabled(!model.preferences.masterEnabled)

                Section {
                    Toggle("Monthly reset", isOn: preferenceBinding(\.cursorMonthlyReset))
                } header: {
                    Text("Cursor")
                } footer: {
                    Text("Monthly reset alerts fire when Cursor's monthly allowance renews.")
                }
                .disabled(!model.preferences.masterEnabled)

                Section {
                    Toggle("Show Codex Spark meters", isOn: codexSparkBinding)
                } header: {
                    Text("Display")
                } footer: {
                    Text("Adds Spark's 5-hour and weekly meters to Codex wherever usage is shown. On the tall Home Screen widget, Codex expands and OpenRouter's section makes room for it.")
                }

                Section {
                    disclosureRow(
                        title: "Stored on this device",
                        systemImage: "iphone.and.arrow.forward",
                        message: AmmoPrivacyDisclosure.localData)
                    disclosureRow(
                        title: "Sent to providers",
                        systemImage: "arrow.up.right",
                        message: AmmoPrivacyDisclosure.providerProcessing)
                } header: {
                    Text("Privacy")
                }

                Section {
                    LabeledContent("Version", value: AmmoAbout.versionDisplay)

                    Link(destination: AmmoPrivacyDisclosure.privacyPolicyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Link(destination: AmmoPrivacyDisclosure.supportURL) {
                        Label("Support", systemImage: "questionmark.circle")
                    }

                    Text(AmmoAbout.credits)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                } footer: {
                    Text(AmmoPrivacyDisclosure.nonAffiliation)
                }

                Section {
                    Button {
                        exportRawUsagePayloads()
                    } label: {
                        Label("Export Raw Usage Payloads", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Exports latest provider response bodies for fixture capture. Authentication headers and token responses are never included.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if model.authorizationStatus == nil {
                    await model.refreshAuthorizationStatus()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await model.refreshAuthorizationStatus() }
            }
            .sheet(item: $payloadExport) { export in
                ActivityShareSheet(items: [export.url])
            }
            .alert("Couldn't Export Payloads", isPresented: payloadExportAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(payloadExportError ?? "Unknown export error")
            }
        }
    }

    private var payloadExportAlertBinding: Binding<Bool> {
        Binding(
            get: { payloadExportError != nil },
            set: { if !$0 { payloadExportError = nil } }
        )
    }

    private func exportRawUsagePayloads() {
        do {
            payloadExport = PayloadExport(url: try RawUsagePayloadStore.makeExportFile())
        } catch {
            payloadExportError = error.localizedDescription
        }
    }

    private func disclosureRow(
        title: String,
        systemImage: String,
        message: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var codexSparkBinding: Binding<Bool> {
        Binding(
            get: { store.showsCodexSpark },
            set: { store.setShowsCodexSpark($0) }
        )
    }

    private var masterBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.masterEnabled },
            set: { enabled in
                Task { await model.setMasterEnabled(enabled) }
            }
        )
    }

    private func preferenceBinding(
        _ keyPath: WritableKeyPath<NotificationPreferences, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { model.preferences[keyPath: keyPath] },
            set: { model.set(keyPath, to: $0) }
        )
    }

    private var notificationPermissionNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notifications are off for Ammo in System Settings. Allow notifications there, then enable them here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Open System Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
        }
    }
}

enum AmmoPrivacyDisclosure {
    static let localData =
        "Credentials stay in iOS Keychain. Account labels, usage snapshots, history, refresh data, and widget preferences stay on this device in Ammo's App Group."
    static let providerProcessing =
        "When you sign in or refresh, Ammo sends requests directly to the provider you chose. That provider processes them under its own privacy policy. Ammo has no developer-operated server."
    static let nonAffiliation =
        "Ammo is an independent app. It is not affiliated with, endorsed by, or sponsored by Anthropic, OpenAI, Anysphere, or OpenRouter."
    static let privacyPolicyURL = URL(
        string: "https://brandon1138.github.io/ammo/privacy-policy/")!
    static let supportURL = URL(
        string: "https://github.com/Brandon1138/ammo/issues")!
}

enum AmmoAbout {
    static let credits = "Made by Brandon Aron · Design by George Began-Mich"

    /// Marketing version and build read from the bundle, so the row can never
    /// drift from what App Store Connect received.
    static var versionDisplay: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

private struct PayloadExport: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
