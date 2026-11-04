import Foundation

/// Claude Code's plan limits, from the unofficial endpoint behind `/usage` (see docs/SPIKES.md, S1).
/// The OAuth token is read from Claude Code's Keychain item and is never logged, stored or refreshed.
public struct ClaudeClient: Sendable {
    public init() {}

    public struct Credentials: Equatable, Sendable {
        public var accessToken: String
        public var expiresAt: Date?
        public var tier: String?

        public init?(json: Data) {
            struct File: Decodable { var claudeAiOauth: OAuth? }
            struct OAuth: Decodable { var accessToken: String; var expiresAt: Double?; var subscriptionType: String? }
            guard let o = (try? JSONDecoder().decode(File.self, from: json))?.claudeAiOauth else { return nil }
            accessToken = o.accessToken
            expiresAt = o.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) }
            tier = o.subscriptionType?.capitalized
        }
    }

    private static let session = URLSession(configuration: .ephemeral)

    public func fetch() async -> PlanSnapshot {
        guard let json = Self.readKeychain(), let c = Credentials(json: json) else {
            return PlanSnapshot(id: .claude, problem: .notSetUp("Sign in to Claude Code with a Claude plan"))
        }
        func failed(_ message: String) -> PlanSnapshot { PlanSnapshot(id: .claude, tier: c.tier, problem: .failed(message)) }
        // Never refresh the token ourselves: that rotates the refresh token and can sign Claude Code out.
        if let expires = c.expiresAt, expires < Date() { return failed("Open Claude Code to refresh sign-in") }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 15)
        request.setValue("Bearer \(c.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        guard let (data, response) = try? await Self.session.data(for: request) else { return failed("Couldn't reach Claude") }
        return Self.snapshot(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data, tier: c.tier, now: Date())
    }

    static func snapshot(status: Int, data: Data, tier: String?, now: Date) -> PlanSnapshot {
        func failed(_ message: String) -> PlanSnapshot { PlanSnapshot(id: .claude, tier: tier, problem: .failed(message)) }
        switch status {
        case 200:
            guard let windows = try? parseUsage(data) else { return failed("Claude usage changed format") }
            return PlanSnapshot(id: .claude, tier: tier, windows: windows, asOf: now)
        case 401, 403: return failed("Open Claude Code to refresh sign-in")
        case 429: return failed("Claude is limiting usage checks")
        default: return failed("Claude usage returned \(status)")
        }
    }

    static func parseUsage(_ data: Data) throws -> [LimitWindow] {
        struct Usage: Decodable { var five_hour: Window; var seven_day: Window? }
        struct Window: Decodable { var utilization: Double; var resets_at: String? }
        let u = try JSONDecoder().decode(Usage.self, from: data)
        return try [(WindowKind.fiveHour, u.five_hour), (.weekly, u.seven_day)].compactMap { kind, w in
            // No reset time means the window hasn't started, which reads as full.
            try w.map { LimitWindow(kind: kind, usedPercent: $0.utilization, resetsAt: try $0.resets_at.map { try Date($0, strategy: .iso8601) } ?? .distantPast) }
        }
    }

    /// Goes through /usr/bin/security, which Claude Code itself uses, so the item's access list
    /// already trusts it and macOS doesn't prompt on every token refresh.
    static func readKeychain() -> Data? {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }
}
