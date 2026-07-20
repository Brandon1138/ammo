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

/// Drives Cursor's callback-less first-party login. Cursor binds a browser
/// approval to a UUID + PKCE challenge; Ammo polls until the token pair is ready.
@MainActor
final class CursorAuthFlow: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var pollTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<OAuthTokens, Error>?

    struct CancelledError: Error, CustomStringConvertible {
        var description: String { "Sign-in was cancelled" }
    }

    struct TimeoutError: Error, CustomStringConvertible {
        var description: String { "Cursor sign-in timed out — try again" }
    }

    func signIn() async throws -> OAuthTokens {
        defer {
            pollTask?.cancel()
            pollTask = nil
            session = nil
        }

        let pkce = PKCE()
        let uuid = UUID()
        let provider = CursorProvider()
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<OAuthTokens, Error>) in
            self.continuation = continuation
            pollTask = Task { [weak self] in
                guard let self else { return }
                do {
                    // Cursor 3.7.27 polls every 500 ms. Give a phone user five
                    // minutes to complete an external identity-provider login.
                    for _ in 0..<600 {
                        try Task.checkCancellation()
                        if let tokens = try await provider.pollForTokens(
                            uuid: uuid, verifier: pkce.verifier) {
                            finish(tokens: tokens)
                            return
                        }
                        try await Task.sleep(for: .milliseconds(500))
                    }
                    fail(TimeoutError())
                } catch is CancellationError {
                    // Dismissing the auth sheet is an expected cancellation path.
                } catch {
                    fail(error)
                }
            }

            let session = ASWebAuthenticationSession(
                url: CursorProvider.authorizationRequestURL(pkce: pkce, uuid: uuid),
                callbackURLScheme: nil
            ) { [weak self] _, _ in
                Task { @MainActor in self?.abort() }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                fail(UsageError.notAuthenticated("cursor: unable to start browser sign-in"))
            }
        }
    }

    private func finish(tokens: OAuthTokens) {
        guard let continuation else { return }
        self.continuation = nil
        session?.cancel()
        continuation.resume(returning: tokens)
    }

    private func fail(_ error: Error) {
        guard let continuation else { return }
        self.continuation = nil
        pollTask?.cancel()
        session?.cancel()
        continuation.resume(throwing: error)
    }

    private func abort() {
        fail(CancelledError())
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}
