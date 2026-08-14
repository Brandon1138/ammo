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
final class LoopbackServer: @unchecked Sendable {
    private static let maximumHeaderBytes = 16 * 1024
    private static let headerTerminator = Data("\r\n\r\n".utf8)
    private let listener: NWListener
    private let readiness = ReadinessLatch()

    enum ReadinessError: Error, CustomStringConvertible {
        case invalidPort(UInt16)
        case failed(String)
        case cancelled
        case timedOut
        case unexpectedPort(expected: UInt16, actual: UInt16)

        var description: String {
            switch self {
            case .invalidPort(let port):
                "Invalid loopback port \(port)"
            case .failed(let detail):
                "Loopback listener failed: \(detail)"
            case .cancelled:
                "Loopback listener was cancelled"
            case .timedOut:
                "Loopback listener did not become ready in time"
            case .unexpectedPort(let expected, let actual):
                "Loopback listener bound port \(actual), expected \(expected)"
            }
        }
    }

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
        // Exclusive binding makes port contention fail visibly. PKCE prevents
        // token theft, but shared delivery would still cause sign-in denial.
        parameters.allowLocalEndpointReuse = false
        parameters.requiredInterfaceType = .loopback
        guard let requestedPort = NWEndpoint.Port(rawValue: port) else {
            throw ReadinessError.invalidPort(port)
        }
        let listener = try NWListener(using: parameters, on: requestedPort)
        self.listener = listener
        listener.newConnectionHandler = { connection in
            guard Self.isLoopback(connection.endpoint) else {
                connection.cancel()
                return
            }
            connection.start(queue: .global())
            Self.handle(connection, expectedState: expectedState, onCode: onCode)
        }
        listener.stateUpdateHandler = { [weak listener, readiness] state in
            switch state {
            case .ready:
                guard let port = listener?.port?.rawValue else {
                    readiness.resolve(.failure(ReadinessError.failed("ready without a bound port")))
                    return
                }
                readiness.resolve(.success(port))
            case .failed(let error):
                readiness.resolve(.failure(ReadinessError.failed(String(describing: error))))
            case .cancelled:
                readiness.resolve(.failure(ReadinessError.cancelled))
            default:
                break
            }
        }
        listener.start(queue: .global())
    }

    /// The port the listener actually bound, once it is ready. `nil` before then.
    var boundPort: UInt16? {
        listener.port?.rawValue
    }

    /// Browser launch must wait for an exclusive, exact-port bind. Otherwise
    /// provider redirect can race listener startup or reach another process.
    func waitUntilReady(
        expectedPort: UInt16? = nil,
        timeout: TimeInterval = 3
    ) async throws -> UInt16 {
        let port = try await readiness.wait(timeout: timeout)
        if let expectedPort, port != expectedPort {
            throw ReadinessError.unexpectedPort(expected: expectedPort, actual: port)
        }
        return port
    }

    func stop() {
        listener.cancel()
    }

    private static func handle(_ connection: NWConnection,
                               expectedState: String,
                               onCode: @escaping @Sendable (String) -> Void) {
        receiveHeaders(connection,
                       buffer: Data(),
                       expectedState: expectedState,
                       onCode: onCode)
    }

    private static func receiveHeaders(
        _ connection: NWConnection,
        buffer: Data,
        expectedState: String,
        onCode: @escaping @Sendable (String) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4 * 1024) {
            data, _, isComplete, error in
            guard error == nil else {
                connection.cancel()
                return
            }

            var accumulated = buffer
            if let data {
                accumulated.append(data)
            }

            guard accumulated.count <= maximumHeaderBytes else {
                send(Reply(status: "431 Request Header Fields Too Large",
                           message: Page.notFound,
                           code: nil),
                     over: connection,
                     onCode: onCode)
                return
            }

            if let terminator = accumulated.range(of: headerTerminator) {
                let headers = accumulated[..<terminator.upperBound]
                guard let target = requestTarget(from: Data(headers)) else {
                    send(Reply(status: "400 Bad Request",
                               message: Page.notFound,
                               code: nil),
                         over: connection,
                         onCode: onCode)
                    return
                }
                send(reply(forTarget: target, expectedState: expectedState),
                     over: connection,
                     onCode: onCode)
                return
            }

            guard !isComplete else {
                send(Reply(status: "400 Bad Request",
                           message: Page.notFound,
                           code: nil),
                     over: connection,
                     onCode: onCode)
                return
            }

            receiveHeaders(connection,
                           buffer: accumulated,
                           expectedState: expectedState,
                           onCode: onCode)
        }
    }

    private static func requestTarget(from headers: Data) -> String? {
        guard let request = String(data: headers, encoding: .utf8),
              let requestLine = request.components(separatedBy: "\r\n").first
        else { return nil }
        let fields = requestLine.split(separator: " ")
        guard fields.count == 3,
              fields[0] == "GET",
              fields[2].hasPrefix("HTTP/1.")
        else { return nil }
        return String(fields[1])
    }

    private static func send(
        _ reply: Reply,
        over connection: NWConnection,
        onCode: @escaping @Sendable (String) -> Void
    ) {
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

private final class ReadinessLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<UInt16, Error>?
    private var continuation: CheckedContinuation<UInt16, Error>?

    func wait(timeout: TimeInterval) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
                return
            }
            self.continuation = continuation
            lock.unlock()

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.resolve(.failure(LoopbackServer.ReadinessError.timedOut))
            }
        }
    }

    func resolve(_ result: Result<UInt16, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
