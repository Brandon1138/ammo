import Foundation
import Network

/// Minimal HTTP listener on localhost that captures the OAuth redirect during
/// Codex sign-in (SPEC.md §Codex onboarding). ASWebAuthenticationSession can't
/// intercept http://localhost redirects itself, so the provider's browser page
/// connects to this listener over device loopback; we grab `code` from the
/// query string and answer with a tiny "return to Ammo" page.
final class LoopbackServer {
    private let listener: NWListener

    init(port: UInt16 = 1455,
         onCode: @escaping @Sendable (_ code: String, _ state: String?) -> Void) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            Self.handle(connection, onCode: onCode)
        }
        listener.start(queue: .global())
    }

    func stop() {
        listener.cancel()
    }

    private static func handle(_ connection: NWConnection,
                               onCode: @escaping @Sendable (String, String?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, _, _ in
            guard let data,
                  let request = String(data: data, encoding: .utf8),
                  let target = request.split(separator: " ").dropFirst().first, // "GET /path?q HTTP/1.1"
                  let components = URLComponents(string: String(target))
            else {
                connection.cancel()
                return
            }
            func query(_ name: String) -> String? {
                components.queryItems?.first { $0.name == name }?.value
            }

            var status = "404 Not Found"
            var message = "Not found."
            if components.path == "/auth/callback" {
                if let code = query("code") {
                    status = "200 OK"
                    message = "Signed in — return to Ammo."
                    onCode(code, query("state"))
                } else {
                    status = "400 Bad Request"
                    message = query("error_description") ?? query("error") ?? "No code in callback."
                }
            }
            let html = """
            <!doctype html><meta name="viewport" content="width=device-width, initial-scale=1">
            <body style="font-family:-apple-system,sans-serif;text-align:center;padding-top:4em">
            <h2>\(message)</h2></body>
            """
            let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n"
                + "Content-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            connection.send(content: Data(response.utf8),
                            completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
