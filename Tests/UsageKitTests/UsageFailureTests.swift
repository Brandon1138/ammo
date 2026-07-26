import Foundation
import Testing
@testable import UsageKit

@Suite struct UsageFailureTests {
    @Test func classifiesTransportFailures() {
        #expect(UsageFailureClassifier.classify(URLError(.timedOut)) == .timedOut)
        #expect(UsageFailureClassifier.classify(URLError(.notConnectedToInternet)) == .offline)
        #expect(UsageFailureClassifier.classify(URLError(.cannotConnectToHost)) == .serviceUnavailable)
    }

    @Test func classifiesProviderFailures() {
        #expect(UsageFailureClassifier.classify(UsageError.http(status: 429, body: "")) == .rateLimited)
        #expect(UsageFailureClassifier.classify(UsageError.http(status: 401, body: "")) == .authentication)
        #expect(UsageFailureClassifier.classify(UsageError.http(status: 503, body: "")) == .serviceUnavailable)
        #expect(UsageFailureClassifier.classify(UsageError.malformedResponse("missing field")) == .invalidResponse)
    }

    @Test func honoursCategoriesDeclaredByCallerErrors() {
        struct SignInTimedOut: UsageFailureRepresentable {
            var usageFailureKind: UsageFailureKind { .timedOut }
        }
        // Without the declared category this would fall through to .unknown
        // and the user would see the generic "something interrupted" copy.
        #expect(UsageFailureClassifier.classify(SignInTimedOut()) == .timedOut)
    }

    @Test func sanitizesDescriptionsPersistedByOlderBuilds() {
        let previousBuildTimeout = "Error Domain=NSURLErrorDomain Code=-1001 The request timed out"
        #expect(UsageFailureClassifier.classifyLegacyDescription(previousBuildTimeout) == .timedOut)
        #expect(UsageFailureClassifier.classifyLegacyDescription("HTTP 429: Too Many Requests") == .rateLimited)
    }
}
