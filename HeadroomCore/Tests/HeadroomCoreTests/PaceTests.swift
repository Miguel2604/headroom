import Foundation
import Testing
@testable import HeadroomCore

let utc = TimeZone(identifier: "UTC")!

func at(_ s: String) -> Date { try! Date(s, strategy: .iso8601) }

/// The mockups' sample state, Wednesday 4 November at 09:41.
let sampleNow = at("2026-11-04T09:41:00Z")
let sampleClaude = PlanSnapshot(id: .claude, tier: "Max", windows: [
    LimitWindow(kind: .fiveHour, usedPercent: 62, resetsAt: at("2026-11-04T12:12:00Z")),
    LimitWindow(kind: .weekly, usedPercent: 26, resetsAt: at("2026-11-08T09:00:00Z")),
], asOf: sampleNow)
let sampleCodex = PlanSnapshot(id: .codex, tier: "Plus", windows: [
    LimitWindow(kind: .fiveHour, usedPercent: 23, resetsAt: at("2026-11-04T12:53:00Z")),
    LimitWindow(kind: .weekly, usedPercent: 57, resetsAt: at("2026-11-04T14:20:00Z")),
], asOf: sampleNow)

@Suite struct PaceTests {
    @Test func onPace() {
        let w = LimitWindow(kind: .fiveHour, usedPercent: 40, resetsAt: sampleNow + 150 * 60)
        let p = w.pace(at: sampleNow)
        #expect(p.left == 60)
        #expect(p.evenLeft == 50)
        #expect(p.status == .onPace)
    }

    @Test func runningOut() {
        let p = sampleClaude.windows[0].pace(at: sampleNow)
        #expect(p.left == 38)
        #expect(abs(p.evenLeft - 50.33) < 0.01)
        #expect(p.status == .runningOut)
        let runout = try! #require(p.runout)
        #expect(abs(runout.timeIntervalSince(sampleNow) - 38 * 149 / 62 * 60) < 1)
    }

    @Test func limitReached() {
        let w = LimitWindow(kind: .fiveHour, usedPercent: 100, resetsAt: sampleNow + 60 * 60)
        #expect(w.pace(at: sampleNow).status == .limitReached)
        #expect(w.pace(at: sampleNow).left == 0)
    }

    @Test func overLimitClampsToZeroLeft() {
        let w = LimitWindow(kind: .fiveHour, usedPercent: 120, resetsAt: sampleNow + 60 * 60)
        #expect(w.pace(at: sampleNow).left == 0)
    }

    @Test func expiringUnused() {
        let p = sampleCodex.windows[1].pace(at: sampleNow)
        #expect(p.left == 43)
        #expect(p.status == .expiringUnused)
    }

    @Test func passedResetMeansFull() {
        let w = LimitWindow(kind: .fiveHour, usedPercent: 100, resetsAt: sampleNow - 1)
        let p = w.pace(at: sampleNow)
        #expect(p.left == 100)
        #expect(p.status == .reset)
        #expect(p.resetsAt == nil)
    }

    @Test func unusedWindowNeverRunsOut() {
        let w = LimitWindow(kind: .weekly, usedPercent: 0, resetsAt: sampleNow + 3 * 86400)
        let p = w.pace(at: sampleNow)
        #expect(p.runout == nil)
        #expect(p.status == .onPace)
    }

    @Test func dotsMatchTheMockups() {
        // Mockup: 38% left, even pace 50%, 16 dots.
        let d = dots(left: 38, evenLeft: 50, count: 16)
        #expect(d == Array(repeating: .on, count: 6) + [.off, .pace] + Array(repeating: .off, count: 8))
        // Limit reached card: 0% left, pace 22%, 14 dots.
        #expect(dots(left: 0, evenLeft: 22, count: 14)[2] == .pace)
        // The pace dot never falls off the start.
        #expect(dots(left: 43, evenLeft: 3, count: 14).first == .pace)
        #expect(dots(left: 43, evenLeft: 3, count: 14).filter { $0 == .on }.count == 5)
    }
}

@Suite struct TimelineTests {
    @Test func everyFiveMinutesForAnHour() {
        let s = Snapshot(claude: PlanSnapshot(id: .claude, windows: [LimitWindow(kind: .fiveHour, usedPercent: 10, resetsAt: sampleNow + 4 * 3600)]), codex: PlanSnapshot(id: .codex))
        let dates = timelineDates(s, from: sampleNow)
        #expect(dates.count == 12)
        #expect(dates.first == sampleNow)
        #expect(dates.last == sampleNow + 55 * 60)
    }

    @Test func stopsAtTheNextReset() {
        let s = Snapshot(claude: sampleClaude, codex: PlanSnapshot(id: .codex, windows: [
            LimitWindow(kind: .fiveHour, usedPercent: 10, resetsAt: sampleNow + 12 * 60),
            LimitWindow(kind: .weekly, usedPercent: 10, resetsAt: sampleNow - 60),
        ]))
        #expect(timelineDates(s, from: sampleNow) == [0, 5, 10, 12].map { sampleNow + Double($0) * 60 })
    }

    @Test func noDataStillHasAnEntry() {
        #expect(timelineDates(Snapshot(claude: PlanSnapshot(id: .claude), codex: PlanSnapshot(id: .codex)), from: sampleNow).count == 12)
    }
}
