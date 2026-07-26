import Foundation
import Network
import Testing
import UsageKit
@testable import Ammo

@Suite("Sign-in flows")
struct SignInFlowTests {
    @Test("The Codex callback is rejected unless it echoes our exact state")
    func codexCallbackStateIsMandatory() {
        #expect(CodexAuthFlow.isCallbackStateValid(received: "abc", expected: "abc"))
        #expect(!CodexAuthFlow.isCallbackStateValid(received: "other", expected: "abc"))
        // A stateless redirect must not pass: anything that can reach the
        // loopback listener could otherwise inject an authorization code.
        #expect(!CodexAuthFlow.isCallbackStateValid(received: nil, expected: "abc"))
        #expect(!CodexAuthFlow.isCallbackStateValid(received: "", expected: "abc"))
    }

    @Test("A Cursor sign-in timeout reaches the user as a timeout")
    func cursorTimeoutKeepsItsCategory() {
        #expect(UsageFailureClassifier.classify(CursorAuthFlow.TimeoutError()) == .timedOut)
    }
}

@Suite("Codex loopback listener")
struct LoopbackServerTests {
    private let expectedState = "expected-state"

    // MARK: - Callback handling

    @Test("A callback that echoes our state yields its code")
    func matchingStateYieldsCode() {
        let reply = LoopbackServer.reply(
            forTarget: "/auth/callback?code=real-code&state=expected-state",
            expectedState: expectedState)

        #expect(reply == LoopbackServer.Reply(status: "200 OK",
                                              message: LoopbackServer.Page.signedIn,
                                              code: "real-code"))
    }

    @Test("A wrong or missing state is answered and dropped, never surfaced as a code")
    func wrongStateIsDropped() {
        let targets = [
            "/auth/callback?code=injected&state=attacker-state",
            "/auth/callback?code=injected",
            "/auth/callback?code=injected&state=",
            "/auth/callback?state=expected-state",
        ]
        for target in targets {
            let reply = LoopbackServer.reply(forTarget: target, expectedState: expectedState)
            #expect(reply.code == nil, "\(target) must not produce a code")
            #expect(reply.status == "400 Bad Request")
            #expect(reply.message == LoopbackServer.Page.noCallbackCode)
        }
    }

    @Test("An unknown path is a 404 and never a code")
    func unknownPathIsNotFound() {
        let reply = LoopbackServer.reply(forTarget: "/?code=injected&state=expected-state",
                                         expectedState: expectedState)

        #expect(reply.code == nil)
        #expect(reply.status == "404 Not Found")
        #expect(reply.message == LoopbackServer.Page.notFound)
    }

    // MARK: - Rendered page

    @Test("Callback-supplied text is never rendered into the page")
    func callbackTextIsNeverRendered() {
        let hostile = [
            "/auth/callback?error=access_denied&error_description=%3Cscript%3Ealert(1)%3C%2Fscript%3E",
            "/auth/callback?error=%3Cimg%20src%3Dx%20onerror%3Dalert(1)%3E",
            "/auth/callback?code=injected&state=wrong&error_description=%3Cb%3Ehi%3C%2Fb%3E",
        ]
        for target in hostile {
            let reply = LoopbackServer.reply(forTarget: target, expectedState: expectedState)
            // The page copy is a constant, so nothing from the query string —
            // markup or otherwise — can reach the user's browser.
            #expect(reply.message == LoopbackServer.Page.noCallbackCode)
            #expect(!reply.message.contains("<"))
            #expect(!reply.message.contains("script"))
            #expect(!reply.message.contains("alert"))
        }
    }

    // MARK: - Binding

    @Test("Only loopback peers are accepted")
    func nonLoopbackPeersAreRejected() {
        #expect(LoopbackServer.isLoopback(.hostPort(host: .ipv4(.loopback), port: 1455)))
        #expect(LoopbackServer.isLoopback(.hostPort(host: .ipv6(.loopback), port: 1455)))
        #expect(!LoopbackServer.isLoopback(
            .hostPort(host: .ipv4(IPv4Address("192.168.1.20")!), port: 1455)))
        #expect(!LoopbackServer.isLoopback(
            .hostPort(host: .ipv6(IPv6Address("fe80::1")!), port: 1455)))
        #expect(!LoopbackServer.isLoopback(.hostPort(host: .name("example.com", nil), port: 1455)))
        #expect(!LoopbackServer.isLoopback(
            .service(name: "x", type: "_http._tcp", domain: "", interface: nil)))
    }

    /// End to end over a real socket: the listener has to actually bind on the
    /// loopback interface, and a rejected callback must not take the session
    /// down with it — the user is still finishing sign-in in the browser.
    @Test("The bound listener survives a rejected callback and still accepts ours")
    func boundListenerSurvivesRejectedCallback() async throws {
        let codes = Locked<[String]>([])
        let server = try LoopbackServer(port: 0, expectedState: expectedState) { code in
            codes.mutate { $0.append(code) }
        }
        defer { server.stop() }
        let port = try await Self.boundPort(of: server)

        let injected = try await Self.get(port: port,
                                          target: "/auth/callback?code=injected&state=wrong")
        #expect(injected.contains("400 Bad Request"))
        #expect(!injected.contains("injected"))

        let hostile = try await Self.get(
            port: port,
            target: "/auth/callback?error_description=%3Cscript%3Ealert(1)%3C%2Fscript%3E")
        #expect(hostile.contains("400 Bad Request"))
        #expect(!hostile.contains("<script>"))
        #expect(!hostile.contains("alert"))

        let real = try await Self.get(port: port,
                                      target: "/auth/callback?code=real-code&state=expected-state")
        #expect(real.contains("200 OK"))
        #expect(codes.value == ["real-code"])
    }

    @Test("A callback split across TCP writes is parsed only after complete headers arrive")
    func fragmentedCallbackIsAccepted() async throws {
        let codes = Locked<[String]>([])
        let server = try LoopbackServer(port: 0, expectedState: expectedState) { code in
            codes.mutate { $0.append(code) }
        }
        defer { server.stop() }
        let port = try await Self.boundPort(of: server)

        let response = try await Self.get(
            port: port,
            fragments: [
                "GET /auth/call",
                "back?code=fragmented-code&state=expected-state HTTP/1.1\r\nHo",
                "st: localhost\r\nConnection: close\r\n",
                "\r\n",
            ])

        #expect(response.contains("200 OK"))
        #expect(codes.value == ["fragmented-code"])
    }

    // MARK: - Helpers

    private struct ListenerError: Error, CustomStringConvertible {
        let description: String
    }

    private static func boundPort(of server: LoopbackServer) async throws -> UInt16 {
        for _ in 0..<100 {
            if let port = server.boundPort, port != 0 { return port }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ListenerError(description: "The loopback listener never bound a port")
    }

    /// Raw TCP rather than URLSession: the point of the test is what the socket
    /// answers, without an HTTP client's redirect or caching behaviour.
    private static func get(port: UInt16, target: String) async throws -> String {
        let request = "GET \(target) HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        return try await get(port: port, fragments: [request])
    }

    private static func get(port: UInt16, fragments: [String]) async throws -> String {
        let connection = NWConnection(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp)
        defer { connection.cancel() }
        connection.start(queue: .global())

        for fragment in fragments {
            try await withCheckedThrowingContinuation {
                (cont: CheckedContinuation<Void, Error>) in
                connection.send(content: Data(fragment.utf8),
                                completion: .contentProcessed { error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                })
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let data: Data? = try await withCheckedThrowingContinuation { cont in
            connection.receiveMessage { data, _, _, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: data) }
            }
        }
        guard let data else {
            throw ListenerError(description: "The listener closed without answering")
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Minimal box so a `@Sendable` callback can record what it saw.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        lock.withLock { stored }
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.withLock { body(&stored) }
    }
}
