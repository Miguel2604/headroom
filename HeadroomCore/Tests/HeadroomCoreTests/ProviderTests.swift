import Foundation
import Testing
@testable import HeadroomCore

private func fixture(_ name: String) -> URL {
    Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!
}

/// A throwaway `~/.codex/sessions` tree.
private func sessions(_ files: [(path: String, contents: String, age: TimeInterval)]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "codex-\(UUID().uuidString)")
    for f in files {
        let url = root.appending(path: f.path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try f.contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date() - f.age], ofItemAtPath: url.path)
    }
    return root
}

@Suite struct CodexProviderTests {
    let line = try! String(contentsOf: fixture("codex-token-count.jsonl"), encoding: .utf8)

    @Test func readsTheLastRateLimitsLine() throws {
        let root = try sessions([("2026/11/04/rollout-a.jsonl", line, 0)])
        let plan = CodexReader(sessions: root).read()
        #expect(plan.problem == nil)
        #expect(plan.tier == "Plus")
        #expect(plan.asOf == at("2026-11-04T04:24:00.271Z"))
        #expect(plan.windows == [
            LimitWindow(kind: .fiveHour, usedPercent: 31, resetsAt: Date(timeIntervalSince1970: 1793771977), minutes: 300),
            LimitWindow(kind: .weekly, usedPercent: 74, resetsAt: Date(timeIntervalSince1970: 1793812838), minutes: 10080),
        ])
    }

    @Test func fallsBackToAnOlderFile() throws {
        let root = try sessions([
            ("2026/11/03/rollout-old.jsonl", line, 3600),
            ("2026/11/04/rollout-new.jsonl", #"{"type":"session_meta","payload":{}}"# + "\n", 0),
        ])
        #expect(CodexReader(sessions: root).read().windows.count == 2)
    }

    @Test func survivesGarbage() throws {
        let root = try sessions([("2026/11/04/rollout-x.jsonl", "not json\n{\"rate_limits\": 5}\n\u{0}\u{1}", 0)])
        #expect(CodexReader(sessions: root).read().problem == .notSetUp("Run Codex once to see its limits"))
    }

    @Test func missingFolderIsNotSetUp() {
        let plan = CodexReader(sessions: URL(filePath: "/nonexistent/sessions")).read()
        #expect(plan.problem == .notSetUp("Run Codex once to see its limits"))
        #expect(plan.windows.isEmpty)
    }
}

@Suite struct ClaudeProviderTests {
    @Test func parsesUsage() throws {
        let data = try Data(contentsOf: fixture("claude-usage.json"))
        let windows = try ClaudeClient.parseUsage(data)
        #expect(windows.map(\.kind) == [.fiveHour, .weekly])
        #expect(windows.map(\.usedPercent) == [29, 22])
        #expect(abs(windows[0].resetsAt.timeIntervalSince(at("2026-11-04T04:40:00Z")) - 0.33693) < 0.0001)
        #expect(windows[1].resetsAt == at("2026-11-08T16:00:00Z"))
    }

    @Test func rejectsAnUnexpectedShape() {
        #expect(throws: (any Error).self) { try ClaudeClient.parseUsage(Data(#"{"five_hour": null}"#.utf8)) }
        #expect(throws: (any Error).self) { try ClaudeClient.parseUsage(Data("<html>".utf8)) }
    }

    @Test func nullResetMeansUnusedWindow() throws {
        let json = #"{"five_hour":{"utilization":0,"resets_at":null},"seven_day":{"utilization":3,"resets_at":"2026-11-08T16:00:00Z"}}"#
        let windows = try ClaudeClient.parseUsage(Data(json.utf8))
        #expect(windows[0].pace(at: sampleNow).status == .reset)
    }

    @Test func mapsResponsesToStates() throws {
        let good = try Data(contentsOf: fixture("claude-usage.json"))
        let ok = ClaudeClient.snapshot(status: 200, data: good, tier: "Max", now: sampleNow)
        #expect(ok.problem == nil)
        #expect(ok.windows.count == 2)
        #expect(ok.asOf == sampleNow)
        #expect(ok.tier == "Max")
        let failure = { (status: Int, data: Data) in ClaudeClient.snapshot(status: status, data: data, tier: "Max", now: sampleNow).problem }
        #expect(failure(200, Data("{}".utf8)) == .failed("Claude usage changed format"))
        #expect(failure(401, Data()) == .failed("Open Claude Code to refresh sign-in"))
        #expect(failure(429, Data()) == .failed("Claude is limiting usage checks"))
        #expect(failure(503, Data()) == .failed("Claude usage returned 503"))
    }

    @Test func parsesCredentials() throws {
        let c = try #require(ClaudeClient.Credentials(json: Data(contentsOf: fixture("claude-credentials.json"))))
        #expect(c.accessToken == "sk-ant-oat01-test")
        #expect(c.expiresAt == Date(timeIntervalSince1970: 1793800000))
        #expect(c.tier == "Max")
        #expect(ClaudeClient.Credentials(json: Data(#"{"mcpOAuth":{}}"#.utf8)) == nil)
    }
}

@Suite struct SnapshotTests {
    @Test func failureKeepsTheLastGoodNumbers() {
        let failed = PlanSnapshot(id: .claude, problem: .failed("Offline"))
        let merged = failed.keepingData(from: sampleClaude)
        #expect(merged.windows == sampleClaude.windows)
        #expect(merged.asOf == sampleClaude.asOf)
        #expect(merged.tier == "Max")
        #expect(merged.problem == .failed("Offline"))
        // Not set up means the data is gone for real.
        #expect(PlanSnapshot(id: .claude, problem: .notSetUp("x")).keepingData(from: sampleClaude).windows.isEmpty)
    }

    @Test func roundTripsThroughJSON() throws {
        let s = Snapshot(claude: sampleClaude, codex: PlanSnapshot(id: .codex, problem: .notSetUp("Run Codex once")))
        let url = FileManager.default.temporaryDirectory.appending(path: "snapshot-\(UUID().uuidString).json")
        try s.write(to: url)
        #expect(Snapshot.read(from: url) == s)
        #expect(Snapshot.read(from: URL(filePath: "/nonexistent.json")) == nil)
    }
}

@Suite struct FreshnessTests {
    let codex = PlanSnapshot(id: .codex, windows: sampleCodex.windows, asOf: sampleNow - 6 * 3600)

    @Test func claudeGoesStaleWhenTheAppStopsUpdating() {
        var claude = sampleClaude
        claude.asOf = sampleNow - 31 * 60
        let s = Snapshot(claude: claude, codex: codex).flaggingStale(at: sampleNow)
        #expect(s.claude.problem == .failed("Open Headroom to update"))
        #expect(s.claude.windows == claude.windows)
        // Codex data is only as fresh as the last Codex run, so old is normal.
        #expect(s.codex.problem == nil)
        claude.asOf = sampleNow - 10 * 60
        #expect(Snapshot(claude: claude, codex: codex).flaggingStale(at: sampleNow).claude.problem == nil)
    }

    @Test func claudeFetchTimeAloneIsNotAWidgetChange() {
        var a = Snapshot(claude: sampleClaude, codex: codex), b = a
        b.claude.asOf = sampleNow + 300
        #expect(a.forWidgets == b.forWidgets)
        b.claude.windows[0].usedPercent += 1
        #expect(a.forWidgets != b.forWidgets)
        a.claude.problem = .failed("Offline")
        #expect(a.forWidgets != Snapshot(claude: sampleClaude, codex: codex).forWidgets)
    }

    @Test func asOfShowsCodexAndAnythingFailing() {
        var s = Snapshot(claude: sampleClaude, codex: PlanSnapshot(id: .codex, windows: sampleCodex.windows, asOf: at("2026-11-04T04:24:00Z")))
        #expect(asOfLine(s, timeZone: utc) == "Codex 04:24")
        s.claude.problem = .failed("Offline")
        #expect(asOfLine(s, timeZone: utc) == "Claude 09:41 · Codex 04:24")
        #expect(asOfLine(Snapshot(claude: PlanSnapshot(id: .claude), codex: PlanSnapshot(id: .codex)), timeZone: utc) == "")
    }
}
