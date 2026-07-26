import Foundation
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
