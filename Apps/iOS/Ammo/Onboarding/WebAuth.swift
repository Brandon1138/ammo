import AuthenticationServices
import SafariServices
import SwiftUI
import UsageKit

/// SFSafariViewController wrapper for the Claude paste-code flow: the user
/// signs in, the callback page displays the code, they copy it and dismiss.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// Drives the Codex on-device sign-in: loopback listener on :1455 + an
/// ASWebAuthenticationSession showing auth.openai.com. The session never
/// "completes" via callback URL (the redirect goes to our listener), so we
/// cancel it programmatically once the code arrives.
@MainActor
final class CodexAuthFlow: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var server: LoopbackServer?
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<(code: String, state: String?), Error>?

    struct CancelledError: Error, CustomStringConvertible {
        var description: String { "Sign-in was cancelled" }
    }

    func signIn() async throws -> OAuthTokens {
        defer {
            server?.stop()
            server = nil
            session = nil
        }
        let pkce = PKCE()
        let result = try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<(code: String, state: String?), Error>) in
            continuation = cont
            do {
                server = try LoopbackServer { [weak self] code, state in
                    Task { @MainActor in self?.finish(code: code, state: state) }
                }
            } catch {
                continuation = nil
                cont.resume(throwing: error)
                return
            }
            let session = ASWebAuthenticationSession(
                url: CodexProvider.authorizationRequestURL(pkce: pkce),
                callbackURLScheme: nil
            ) { [weak self] _, _ in
                // Only reached when the user dismisses the sheet (or we cancel
                // after finish(), by which point the continuation is nil).
                Task { @MainActor in self?.abort() }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
        guard result.state == nil || result.state == pkce.state else {
            throw UsageError.notAuthenticated("codex: OAuth state mismatch")
        }
        return try await CodexProvider().exchangeCode(result.code, verifier: pkce.verifier)
    }

    private func finish(code: String, state: String?) {
        session?.cancel()
        continuation?.resume(returning: (code, state))
        continuation = nil
    }

    private func abort() {
        continuation?.resume(throwing: CancelledError())
        continuation = nil
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}
