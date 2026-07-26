import Foundation

struct HistoryLink: Equatable {
    static let scheme = "ammo"

    let accountID: UUID
    let windowID: String

    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "history"
        components.queryItems = [
            URLQueryItem(name: "account", value: accountID.uuidString),
            URLQueryItem(name: "window", value: windowID),
        ]
        return components.url
    }

    init(accountID: UUID, windowID: String) {
        self.accountID = accountID
        self.windowID = windowID
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host == "history",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let accountValue = components.queryItems?.first(where: { $0.name == "account" })?.value,
              let accountID = UUID(uuidString: accountValue),
              let windowID = components.queryItems?.first(where: { $0.name == "window" })?.value else {
            return nil
        }
        self.accountID = accountID
        self.windowID = windowID
    }
}
