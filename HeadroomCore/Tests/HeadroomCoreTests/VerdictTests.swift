import Foundation
import Testing
@testable import HeadroomCore

private func plan(_ id: PlanID, fiveHour used: Double, resets: Date, weekly: Double = 10, weeklyResets: Date = sampleNow + 5 * 86400) -> PlanSnapshot {
    PlanSnapshot(id: id, tier: nil, windows: [
        LimitWindow(kind: .fiveHour, usedPercent: used, resetsAt: resets),
        LimitWindow(kind: .weekly, usedPercent: weekly, resetsAt: weeklyResets),
    ], asOf: sampleNow)
}

@Suite struct VerdictTests {
    let noon = at("2026-11-04T12:12:00Z")
    let later = at("2026-11-04T13:30:00Z")

    func verdict(_ claude: PlanSnapshot, _ codex: PlanSnapshot) -> Verdict {
        HeadroomCore.verdict(Snapshot(claude: claude, codex: codex), at: sampleNow, timeZone: utc)
    }

    @Test func mockupSample() {
        #expect(verdict(sampleClaude, sampleCodex) == Verdict(headline: "Use Codex", detail: "Until 12:12 · Claude out ~11:12", use: .codex))
    }

    @Test func oneAtLimit() {
        let v = verdict(plan(.claude, fiveHour: 100, resets: noon), plan(.codex, fiveHour: 10, resets: later))
        #expect(v == Verdict(headline: "Use Codex", detail: "Until 12:12 · Claude at limit", use: .codex))
    }

    @Test func atLimitLosesToRunningOut() {
        let v = verdict(plan(.claude, fiveHour: 95, resets: later), plan(.codex, fiveHour: 100, resets: noon))
        #expect(v.use == .claude)
        #expect(v.detail == "Until 12:12 · Codex at limit")
    }

    @Test func bothOut() {
        let v = verdict(plan(.claude, fiveHour: 100, resets: later), plan(.codex, fiveHour: 100, resets: noon))
        #expect(v == Verdict(headline: "Both out", detail: "Back 12:12", use: nil))
    }

    @Test func bothRunningOut() {
        let v = verdict(plan(.claude, fiveHour: 90, resets: later), plan(.codex, fiveHour: 80, resets: noon))
        #expect(v.headline == "Slow down")
        #expect(v.use == nil)
        #expect(v.detail.hasPrefix("Claude out ~"))
        #expect(v.detail.contains(" · Codex out ~"))
    }

    @Test func weeklyExpiringUnused() {
        let codex = plan(.codex, fiveHour: 10, resets: later, weekly: 57, weeklyResets: at("2026-11-04T14:20:00Z"))
        let v = verdict(plan(.claude, fiveHour: 10, resets: noon), codex)
        #expect(v == Verdict(headline: "Use Codex", detail: "43% expires in 4h 39m", use: .codex))
    }

    @Test func onPace() {
        let v = verdict(plan(.claude, fiveHour: 10, resets: later), plan(.codex, fiveHour: 10, resets: noon))
        #expect(v == Verdict(headline: "On pace", detail: "Either works · next reset 12:12", use: nil))
    }

    @Test func onlyOnePlanAtLimit() {
        let v = verdict(plan(.claude, fiveHour: 100, resets: noon), PlanSnapshot(id: .codex, problem: .notSetUp("Run Codex once")))
        #expect(v == Verdict(headline: "Claude out", detail: "Back 12:12", use: nil))
    }

    @Test func onlyOnePlanRunningOut() {
        let v = verdict(sampleClaude, PlanSnapshot(id: .codex, problem: .notSetUp("Run Codex once")))
        #expect(v == Verdict(headline: "Slow down", detail: "Claude out ~11:12", use: nil))
    }

    @Test func noData() {
        let v = verdict(PlanSnapshot(id: .claude, problem: .failed("Offline")), PlanSnapshot(id: .codex, problem: .notSetUp("Run Codex once")))
        #expect(v == Verdict(headline: "No data", detail: "Set up Claude Code or Codex", use: nil))
    }

    @Test func staleDataPastItsResetCountsAsFull() {
        var claude = plan(.claude, fiveHour: 100, resets: sampleNow - 60)
        claude.problem = .failed("Offline")
        let v = verdict(claude, plan(.codex, fiveHour: 10, resets: noon))
        #expect(v.headline == "On pace")
    }
}

@Suite struct FormatTests {
    @Test func windowNotes() {
        let n = { (w: LimitWindow) in note(for: w, at: sampleNow, timeZone: utc) }
        #expect(n(sampleClaude.windows[0]) == Note(text: "Out ~11:12", style: .pill))
        #expect(n(sampleClaude.windows[1]) == Note(text: "Resets Sun", style: .plain))
        #expect(n(sampleCodex.windows[0]) == Note(text: "Resets 12:53", style: .plain))
        #expect(n(sampleCodex.windows[1]) == Note(text: "Expires in 4h 39m", style: .strong))
        #expect(n(LimitWindow(kind: .fiveHour, usedPercent: 100, resetsAt: at("2026-11-04T12:12:00Z"))) == Note(text: "Back 12:12", style: .pill))
        #expect(n(LimitWindow(kind: .fiveHour, usedPercent: 50, resetsAt: sampleNow - 1)) == Note(text: "Full", style: .plain))
        #expect(n(LimitWindow(kind: .weekly, usedPercent: 10, resetsAt: at("2026-11-05T08:00:00Z"))) == Note(text: "Resets 08:00", style: .plain))
    }

    @Test func accessibilityLabels() {
        let l = { (p: PlanSnapshot, i: Int) in accessibilityLabel(p.id, p.windows[i], at: sampleNow, timeZone: utc) }
        #expect(l(sampleClaude, 0) == "Claude Code 5-hour limit: 38% left, runs out around 11:12")
        #expect(l(sampleClaude, 1) == "Claude Code weekly limit: 74% left, resets Sunday")
        #expect(l(sampleCodex, 1) == "Codex weekly limit: 43% left, unused quota expires in 4 hours 39 minutes")
    }

    @Test func menuBarSummary() {
        let s = { (c: PlanSnapshot, x: PlanSnapshot) in HeadroomCore.menuBarSummary(Snapshot(claude: c, codex: x), at: sampleNow, timeZone: utc) }
        #expect(s(sampleClaude, sampleCodex) == MenuBarSummary(text: "OUT ~11:12", spoken: "Coding quotas: Claude Code runs out around 11:12"))
        let calm = PlanSnapshot(id: .claude, windows: [LimitWindow(kind: .fiveHour, usedPercent: 62, resetsAt: sampleNow + 3600)], asOf: sampleNow)
        #expect(s(calm, sampleCodex) == MenuBarSummary(text: "38%", spoken: "Coding quotas: tightest limit 38 percent left"))
        let out = PlanSnapshot(id: .claude, windows: [LimitWindow(kind: .fiveHour, usedPercent: 100, resetsAt: at("2026-11-04T12:12:00Z"))], asOf: sampleNow)
        #expect(s(out, sampleCodex) == MenuBarSummary(text: "BACK 12:12", spoken: "Coding quotas: Claude Code limit reached, back at 12:12"))
        #expect(s(PlanSnapshot(id: .claude), PlanSnapshot(id: .codex)) == MenuBarSummary(text: "", spoken: "Coding quotas: no data"))
    }

    @Test func durations() {
        #expect(shortDuration(4 * 3600 + 39 * 60 + 30) == "4h 39m")
        #expect(shortDuration(39 * 60) == "39m")
        #expect(spokenDuration(3600 + 60) == "1 hour 1 minute")
    }
}
