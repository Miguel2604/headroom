import Foundation

/// Reads the `rate_limits` Codex CLI writes into `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
/// The format is undocumented, so anything unexpected is skipped rather than thrown.
public struct CodexReader: Sendable {
    public var sessions: URL

    public init(sessions: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/sessions")) {
        self.sessions = sessions
    }

    public func read() -> PlanSnapshot {
        // A brand-new session has no rate_limits yet, so look a few files back.
        for file in newestFiles(limit: 5) {
            if let plan = Self.lastRateLimits(in: file) { return plan }
        }
        return PlanSnapshot(id: .codex, problem: .notSetUp("Run Codex once to see its limits"))
    }

    func newestFiles(limit: Int) -> [URL] {
        let key = URLResourceKey.contentModificationDateKey
        guard let e = FileManager.default.enumerator(at: sessions, includingPropertiesForKeys: [key]) else { return [] }
        return e.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
            .map { ($0, (try? $0.resourceValues(forKeys: [key]).contentModificationDate) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// Scans the file backwards, line by line, and stops at the first usable `rate_limits`.
    static func lastRateLimits(in file: URL) -> PlanSnapshot? {
        guard let data = try? Data(contentsOf: file, options: .alwaysMapped) else { return nil }
        let needle = Data(#""rate_limits""#.utf8)
        var end = data.endIndex
        while end > data.startIndex {
            let start = data[..<end].lastIndex(of: UInt8(ascii: "\n")).map { $0 + 1 } ?? data.startIndex
            let line = data[start..<end]
            if line.range(of: needle) != nil, let plan = parse(line: line) { return plan }
            end = max(start - 1, data.startIndex)
        }
        return nil
    }

    private struct Line: Decodable {
        var timestamp: String?
        var payload: Payload?
        struct Payload: Decodable { var rate_limits: Limits? }
        struct Limits: Decodable { var primary: Window?; var secondary: Window?; var plan_type: String? }
        struct Window: Decodable { var used_percent: Double; var window_minutes: Double; var resets_at: Double }
    }

    static func parse(line: Data) -> PlanSnapshot? {
        guard let l = try? JSONDecoder().decode(Line.self, from: line), let r = l.payload?.rate_limits else { return nil }
        let windows = [(WindowKind.fiveHour, r.primary), (.weekly, r.secondary)].compactMap { kind, w in
            w.map { LimitWindow(kind: kind, usedPercent: $0.used_percent, resetsAt: Date(timeIntervalSince1970: $0.resets_at), minutes: $0.window_minutes) }
        }
        guard !windows.isEmpty else { return nil }
        let asOf = l.timestamp.flatMap { try? Date($0, strategy: .iso8601) }
        return PlanSnapshot(id: .codex, tier: r.plan_type?.capitalized, windows: windows, asOf: asOf)
    }
}
