import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Injectable transport so providers can be tested against fixture data.
public protocol HTTPTransport: Sendable {
    func request(_ req: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func request(_ req: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }
}

extension HTTPTransport {
    func get(_ url: URL, headers: [String: String]) async throws -> Data {
        var req = URLRequest(url: url)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, status) = try await request(req)
        guard (200..<300).contains(status) else {
            throw UsageError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
        return data
    }

    func post(_ url: URL, headers: [String: String], body: Data) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, status) = try await request(req)
        guard (200..<300).contains(status) else {
            throw UsageError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
        return data
    }
}

enum ISO8601 {
    /// Parses ISO 8601 with or without fractional seconds of any precision
    /// (Anthropic sends 6 fractional digits, which ISO8601DateFormatter rejects).
    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = plain.date(from: raw) ?? fractional.date(from: raw) { return d }
        // Trim sub-millisecond precision and retry.
        if let dotRange = raw.range(of: ".") {
            let fracEnd = raw[dotRange.upperBound...].firstIndex { !$0.isNumber } ?? raw.endIndex
            let frac = raw[dotRange.upperBound..<fracEnd]
            let trimmed = raw.replacingCharacters(in: dotRange.upperBound..<fracEnd,
                                                  with: String(frac.prefix(3)))
            return fractional.date(from: trimmed)
        }
        return nil
    }
}

func formURLEncode(_ params: [String: String]) -> Data {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    let body = params
        .map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        .joined(separator: "&")
    return Data(body.utf8)
}
