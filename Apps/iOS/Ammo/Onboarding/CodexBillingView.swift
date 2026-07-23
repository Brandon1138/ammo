import SwiftUI
import UsageKit
@preconcurrency import WebKit

/// A distinct ChatGPT Admin session for organization billing. It does not reuse
/// Codex OAuth credentials: the user signs in inside this persistent WKWebView,
/// and only the parsed balance leaves the browser data store.
struct CodexBillingView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let account: StoredAccount

    @State private var refreshID = UUID()
    @State private var status = "Sign in to the workspace that owns this Codex account."
    @State private var isConnected = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CodexBillingWebView(
                    expectedAccountID: store.codexBillingAccountID(for: account),
                    refreshID: refreshID,
                    onCapture: saveCapture,
                    onStatus: { status = $0 })

                HStack(spacing: 8) {
                    Image(systemName: isConnected ? "checkmark.circle.fill" : "lock.shield")
                        .foregroundStyle(isConnected ? .green : .secondary)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .navigationTitle("ChatGPT billing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        status = "Checking workspace balance…"
                        refreshID = UUID()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Reload billing balance")
                }
            }
        }
    }

    private func saveCapture(_ capture: CodexBillingCapture) {
        do {
            try store.captureCodexBilling(
                responseData: capture.responseData,
                pageText: capture.pageText,
                billingAccountID: capture.billingAccountID,
                for: account)
            isConnected = true
            status = "Workspace balance connected to \(account.label)."
        } catch {
            isConnected = false
            status = "Could not read this workspace balance."
            AmmoLog.refresh.error("Codex billing capture failed: \(String(describing: error), privacy: .private)")
        }
    }
}

private struct CodexBillingCapture {
    let responseData: Data
    let pageText: String?
    let billingAccountID: String
}

private struct CodexBillingWebView: UIViewRepresentable {
    let expectedAccountID: String?
    let refreshID: UUID
    let onCapture: (CodexBillingCapture) -> Void
    let onStatus: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.refreshID = refreshID
        webView.load(URLRequest(url: URL(string: "https://chatgpt.com/admin/billing")!))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.refreshID != refreshID else { return }
        context.coordinator.refreshID = refreshID
        webView.reload()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: CodexBillingWebView
        var refreshID: UUID?
        private var isCapturing = false

        init(parent: CodexBillingWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            parent.onStatus("Loading ChatGPT billing…")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            captureBalance(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation?,
            withError error: Error
        ) {
            parent.onStatus("ChatGPT billing did not finish loading.")
        }

        private func captureBalance(from webView: WKWebView) {
            guard !isCapturing,
                  webView.url?.host?.hasSuffix("chatgpt.com") == true
            else { return }
            isCapturing = true
            parent.onStatus("Checking workspace balance…")

            Task { @MainActor in
                defer { isCapturing = false }
                try? await Task.sleep(for: .seconds(1))
                do {
                    let value = try await webView.callAsyncJavaScript(
                        Self.captureScript,
                        arguments: ["expectedAccountID": parent.expectedAccountID ?? ""],
                        in: nil,
                        contentWorld: .page)
                    guard let result = value as? [String: Any],
                          let json = result["balanceJSON"] as? String,
                          let billingAccountID = result["billingAccountID"] as? String,
                          !billingAccountID.isEmpty
                    else {
                        parent.onStatus("Sign in to ChatGPT to connect workspace billing.")
                        return
                    }
                    parent.onCapture(CodexBillingCapture(
                        responseData: Data(json.utf8),
                        pageText: result["pageText"] as? String,
                        billingAccountID: billingAccountID))
                } catch {
                    parent.onStatus("Sign in, open the Billing page, then tap reload.")
                }
            }
        }

        /// Runs only in the page's same-origin world. The web access token is used
        /// in-place for ChatGPT's own endpoint and is never returned to native code.
        private static let captureScript = #"""
        const sessionResponse = await fetch('/api/auth/session', { credentials: 'include' });
        if (!sessionResponse.ok) throw new Error('No ChatGPT session');
        const session = await sessionResponse.json();
        const token = session?.accessToken;
        if (!token) throw new Error('Sign in required');

        let billingAccountID = expectedAccountID;
        if (!billingAccountID) {
          const payload = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
          const claims = JSON.parse(atob(payload.padEnd(Math.ceil(payload.length / 4) * 4, '=')));
          billingAccountID = claims?.['https://api.openai.com/auth']?.chatgpt_account_id ?? '';
        }
        if (!billingAccountID) throw new Error('No ChatGPT account id');

        const balanceResponse = await fetch(
          `/backend-api/accounts/${encodeURIComponent(billingAccountID)}/remaining_balance`,
          {
            credentials: 'include',
            headers: {
              'Authorization': `Bearer ${token}`,
              'ChatGPT-Account-ID': billingAccountID
            }
          }
        );
        if (!balanceResponse.ok) throw new Error(`Balance HTTP ${balanceResponse.status}`);
        return {
          balanceJSON: await balanceResponse.text(),
          billingAccountID,
          pageText: document.body?.innerText ?? ''
        };
        """#
    }
}
