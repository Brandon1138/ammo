import Foundation
import Network

/// Minimal HTTP listener on localhost that captures the OAuth redirect during
/// Codex sign-in (SPEC.md §Codex onboarding). ASWebAuthenticationSession can't
/// intercept http://localhost redirects itself, so the provider's browser page
/// connects to this listener over device loopback; we grab `code` from the
/// query string and answer with a tiny "return to Ammo" page.
///
/// The listener is constrained to the loopback interface and only accepts
/// loopback peers: on a shared network anything that can reach the device would
/// otherwise be able to post an authorization code to port 1455.
final class LoopbackServer {
    private let listener: NWListener

    /// Every string this listener can render. The page is HTML served to the
    /// user's browser, so nothing from the callback — `error_description` above
    /// all — is ever interpolated into it; a provider or an attacker that can
    /// choose that text would otherwise choose markup.
    enum Page {
        static let signedIn = "Signed in — return to Ammo."
        static let notFound = "Not found."
        static let noCallbackCode = "Sign-in didn't complete. Return to Ammo and try again."
    }

    /// The parsed answer to one request, kept pure so it can be tested without
    /// binding a socket.
    struct Reply: Equatable {
        let status: String
        let message: String
        /// Non-nil only for a callback whose `state` matches the one we sent.
        let code: String?
    }

    init(port: UInt16 = 1455,
         expectedState: String,
         onCode: @escaping @Sendable (_ code: String) -> Void) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { connection in
            guard Self.isLoopback(connection.endpoint) else {
                connection.cancel()
                return
            }
            connection.start(queue: .global())
            Self.handle(connection, expectedState: expectedState, onCode: onCode)
        }
        listener.start(queue: .global())
    }

    /// The port the listener actually bound, once it is ready. `nil` before then.
    var boundPort: UInt16? {
        listener.port?.rawValue
    }

    func stop() {
        listener.cancel()
    }

    private static func handle(_ connection: NWConnection,
                               expectedState: String,
                               onCode: @escaping @Sendable (String) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, _, _ in
            guard let data,
                  let request = String(data: data, encoding: .utf8),
                  let target = request.split(separator: " ").dropFirst().first // "GET /path?q HTTP/1.1"
            else {
                connection.cancel()
                return
            }
            let reply = Self.reply(forTarget: String(target), expectedState: expectedState)
            if let code = reply.code {
                onCode(code)
            }
            let html = """
            <!doctype html><meta name="viewport" content="width=device-width, initial-scale=1">
            <body style="font-family:-apple-system,sans-serif;text-align:center;padding-top:4em">
            <h2>\(reply.message)</h2></body>
            """
            let response = "HTTP/1.1 \(reply.status)\r\nContent-Type: text/html; charset=utf-8\r\n"
                + "Content-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            connection.send(content: Data(response.utf8),
                            completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    /// A callback that doesn't echo our exact `state` is answered and dropped —
    /// never surfaced to the sign-in flow. Failing the whole attempt instead
    /// would let one unsolicited request cancel a sign-in the user is still
    /// completing in the browser, so the listener stays up for the real one.
    static func reply(forTarget target: String, expectedState: String) -> Reply {
        guard let components = URLComponents(string: target) else {
            return Reply(status: "400 Bad Request", message: Page.notFound, code: nil)
        }
        func query(_ name: String) -> String? {
            components.queryItems?.first { $0.name == name }?.value
        }
        guard components.path == "/auth/callback" else {
            return Reply(status: "404 Not Found", message: Page.notFound, code: nil)
        }
        guard let code = query("code"),
              CodexAuthFlow.isCallbackStateValid(received: query("state"),
                                                 expected: expectedState)
        else {
            return Reply(status: "400 Bad Request", message: Page.noCallbackCode, code: nil)
        }
        return Reply(status: "200 OK", message: Page.signedIn, code: code)
    }

    /// `requiredInterfaceType` already keeps the listener off Wi-Fi and cellular;
    /// this rejects anything that still arrives from a non-loopback address.
    static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return address.isLoopback
        case .ipv6(let address): return address.isLoopback
        case .name: return false
        @unknown default: return false
        }
    }
}
