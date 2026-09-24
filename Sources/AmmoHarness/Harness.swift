import Foundation
import UsageKit

#if os(macOS)

/// Development harness: proves the UsageKit adapters against real accounts using the
/// credentials the Claude Code and Codex CLIs already store on this Mac.
///
/// Deliberately never calls refresh(): refreshing with a CLI's refresh token may
/// rotate it and invalidate the CLI's session. If a token is expired, run the CLI
/// once and re-run the harness.
@main
struct Harness {
    static func main() async {
        if CommandLine.arguments.contains("--raw-claude") {
            await runRawClaude()
            return
        }
        print("AMMO harness — \(Self.timestamp())\n")
        async let claude: Void = runClaude()
        async let codex: Void = runCodex()
        _ = await (claude, codex)
    }

    // MARK: - Claude (token from macOS Keychain, same item the CLI uses)

    static func runClaude() async {
        do {
            let creds = try claudeKeychainCredentials()
            if let expiresAt = creds.expiresAt, expiresAt < Date() {
                print(section("CLAUDE", detail: "token expired \(relative(expiresAt)) — run `claude` once to refresh, then retry"))
                return
            }
            let snapshot = try await ClaudeProvider().fetchUsage(tokens: creds.tokens)
            print(render(snapshot, plan: creds.subscriptionType))
        } catch {
            print(section("CLAUDE", detail: "FAILED — \(error)"))
        }
    }

    static func runRawClaude() async {
        do {
            let creds = try claudeKeychainCredentials()
            if let expiresAt = creds.expiresAt, expiresAt < Date() {
                print("CLAUDE token expired — run `claude` once to refresh, then retry")
                return
            }
            var request = URLRequest(url: ClaudeProvider.usageURL)
            for (name, value) in ClaudeProvider.usageHeaders(accessToken: creds.tokens.accessToken) {
                request.setValue(value, forHTTPHeaderField: name)
            }
            let (data, status) = try await URLSessionTransport().request(request)
            print("CLAUDE HTTP \(status)")
            let response = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let block = response?["cedar_ember"] ?? NSNull()
            let cedar = block as? [String: Any]
            let eligible = (cedar?["eligible"] as? Bool).map(String.init) ?? "null"
            let reason = cedar?["ineligible_reason"] as? String ?? "null"
            print("CLAUDE cedar_ember eligible=\(eligible) ineligible_reason=\(reason)")
            let pretty = try JSONSerialization.data(
                withJSONObject: block,
                options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
            )
            print(String(decoding: pretty, as: UTF8.self))
        } catch {
            print("CLAUDE raw FAILED — \(error)")
        }
    }

    struct ClaudeCredentials {
        let tokens: OAuthTokens
        let expiresAt: Date?
        let subscriptionType: String?
    }

    static func claudeKeychainCredentials() throws -> ClaudeCredentials {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UsageError.notAuthenticated("Keychain item 'Claude Code-credentials' not found — is Claude Code logged in?")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let accessToken = oauth["accessToken"] as? String
        else {
            throw UsageError.malformedResponse("unexpected Keychain credential shape")
        }
        let expiresAt = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return ClaudeCredentials(
            tokens: OAuthTokens(accessToken: accessToken),
            expiresAt: expiresAt,
            subscriptionType: oauth["subscriptionType"] as? String
        )
    }

    // MARK: - Codex (token from ~/.codex/auth.json, same file the CLI uses)

    static func runCodex() async {
        do {
            let tokens = try codexFileCredentials()
            let snapshot = try await CodexProvider().fetchUsage(tokens: tokens)
            print(render(snapshot, plan: snapshot.plan))
        } catch {
            print(section("CODEX", detail: "FAILED — \(error)"))
        }
    }

    static func codexFileCredentials() throws -> OAuthTokens {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        let url = URL(fileURLWithPath: home).appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: url) else {
            throw UsageError.notAuthenticated("\(url.path) not found — is Codex logged in?")
        }
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = root["tokens"] as? [String: Any],
            let accessToken = tokens["access_token"] as? String
        else {
            throw UsageError.malformedResponse("unexpected auth.json shape")
        }
        return OAuthTokens(accessToken: accessToken,
                           accountID: tokens["account_id"] as? String)
    }

    // MARK: - Rendering

    static func render(_ snapshot: UsageSnapshot, plan: String?) -> String {
        var out = section(snapshot.provider.rawValue.uppercased(), detail: plan.map { "(\($0))" } ?? "")
        for window in snapshot.windows {
            let bar = Self.bar(percent: window.usedPercent)
            let reset = window.resetsAt.map { "resets \(relative($0))" } ?? ""
            let label = window.label.padding(toLength: 10, withPad: " ", startingAt: 0)
            out += String(format: "  %@ %@ %3.0f%% used   %@\n",
                          label, bar, window.usedPercent, reset)
        }
        if let banked = snapshot.bankedResets, banked.count > 0 {
            out += "  resets available: \(banked.count)"
            if let expiresAt = banked.expiresAt {
                out += " (use by \(Self.timestamp(expiresAt)))"
            }
            if !banked.usableNow { out += " (not usable now)" }
            out += "\n"
        }
        if snapshot.windows.isEmpty {
            out += "  (no active limit windows reported)\n"
        }
        return out
    }

    static func section(_ name: String, detail: String) -> String {
        "\(name) \(detail)\n"
    }

    static func bar(percent: Double, width: Int = 20) -> String {
        let filled = min(width, max(0, Int((percent / 100 * Double(width)).rounded())))
        return String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func timestamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

#else

/// `ammo-harness` reads credentials from the Mac's Keychain and home directory, so it
/// is intentionally unavailable on iOS. This fallback lets the package be indexed by
/// Xcode for the Simulator while keeping the executable macOS-only in practice.
@main
struct Harness {
    static func main() {
        fatalError("ammo-harness can only run on macOS")
    }
}

#endif
