import Foundation

/// Stable, non-technical categories that an app can safely persist and present.
/// The underlying error remains available to the caller for private logging.
public enum UsageFailureKind: String, Codable, Equatable, Sendable {
    case timedOut
    case rateLimited
    case offline
    case authentication
    case serviceUnavailable
    case invalidResponse
    case unavailable
    case unknown
}

public enum UsageFailureClassifier {
    public static func classify(_ error: any Error) -> UsageFailureKind {
        if let usageError = error as? UsageError {
            switch usageError {
            case .http(let status, _):
                return classifyHTTPStatus(status)
            case .malformedResponse:
                return .invalidResponse
            case .notAuthenticated:
                return .authentication
            }
        }

        if let urlError = error as? URLError {
            return classifyURLErrorCode(urlError.code)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return classifyURLErrorCode(URLError.Code(rawValue: nsError.code))
        }
        if error is DecodingError {
            return .invalidResponse
        }
        return .unknown
    }

    /// Converts errors persisted by older Ammo builds without ever displaying
    /// those raw descriptions again.
    public static func classifyLegacyDescription(_ description: String) -> UsageFailureKind {
        let value = description.lowercased()
        if value.contains("429") || value.contains("rate limit") || value.contains("too many requests") {
            return .rateLimited
        }
        if value.contains("-1001") || value.contains("timed out") || value.contains("timeout") {
            return .timedOut
        }
        if value.contains("-1009") || value.contains("not connected to the internet") || value.contains("offline") {
            return .offline
        }
        if value.contains("http 401") || value.contains("http 403") ||
            value.contains("not authenticated") || value.contains("token expired") ||
            value.contains("no credentials") || value.contains("re-import") {
            return .authentication
        }
        if value.contains("malformed response") || value.contains("decoding") {
            return .invalidResponse
        }
        if value.contains("http 5") || value.contains("-1003") || value.contains("-1004") {
            return .serviceUnavailable
        }
        if value.contains("not supported yet") {
            return .unavailable
        }
        return .unknown
    }

    private static func classifyHTTPStatus(_ status: Int) -> UsageFailureKind {
        switch status {
        case 401, 403:
            .authentication
        case 408, 504:
            .timedOut
        case 429:
            .rateLimited
        case 500...599:
            .serviceUnavailable
        default:
            .unknown
        }
    }

    private static func classifyURLErrorCode(_ code: URLError.Code) -> UsageFailureKind {
        switch code {
        case .timedOut:
            .timedOut
        case .notConnectedToInternet, .networkConnectionLost,
             .internationalRoamingOff, .dataNotAllowed:
            .offline
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            .serviceUnavailable
        case .userAuthenticationRequired, .userCancelledAuthentication:
            .authentication
        default:
            .unknown
        }
    }
}
