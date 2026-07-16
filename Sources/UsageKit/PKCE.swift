import Foundation
import CryptoKit

/// PKCE (RFC 7636) material for one OAuth authorization attempt, plus the CSRF
/// `state` value. Generate a fresh instance per attempt and keep it until the
/// code exchange completes.
public struct PKCE: Sendable {
    public let verifier: String
    public let challenge: String
    public let state: String

    public init() {
        self.init(verifier: Data.cryptoRandom(count: 64).base64URLEncoded,
                  state: Data.cryptoRandom(count: 32).base64URLEncoded)
    }

    /// Internal so tests can pin the verifier to the RFC 7636 vector.
    init(verifier: String, state: String) {
        self.verifier = verifier
        self.challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        self.state = state
    }
}

extension Data {
    /// SystemRandomNumberGenerator is documented cryptographically secure on
    /// Apple platforms (arc4random_buf).
    static func cryptoRandom(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        var data = Data(capacity: count)
        for _ in 0..<count { data.append(UInt8.random(in: .min ... .max, using: &generator)) }
        return data
    }

    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
