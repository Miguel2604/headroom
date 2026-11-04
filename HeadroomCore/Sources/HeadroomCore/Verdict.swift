import Foundation

public struct Verdict: Equatable, Sendable {
    public var headline: String
    public var detail: String
    /// The plan to use, when there is a clear answer.
    public var use: PlanID?
}

/// How a plan stands right now, judged by its worst window.
struct Standing {
    var id: PlanID
    /// 0 fine, 1 running out, 2 at its limit.
    var rank: Int
    /// When every troubled window has reset.
    var backAt: Date?
    /// The earliest projected runout.
    var outAt: Date?

    init?(_ plan: PlanSnapshot, at now: Date) {
        guard !plan.windows.isEmpty else { return nil }
        let paces = plan.windows.map { $0.pace(at: now) }
        let reached = paces.filter { $0.status == .limitReached }
        let running = paces.filter { $0.status == .runningOut }
        id = plan.id
        rank = !reached.isEmpty ? 2 : !running.isEmpty ? 1 : 0
        backAt = (reached + running).compactMap(\.resetsAt).max()
        outAt = running.compactMap(\.runout).min()
    }
}

/// First match wins: one plan in trouble, both in trouble, a weekly window expiring unused, on pace.
public func verdict(_ s: Snapshot, at now: Date, timeZone tz: TimeZone = .current) -> Verdict {
    let clock = { clockTime($0, tz) }
    let standings = s.plans.compactMap { Standing($0, at: now) }
    func trouble(_ p: Standing) -> String {
        p.rank == 2 ? "\(p.id.short) at limit" : "\(p.id.short) out ~\(p.outAt.map(clock) ?? "soon")"
    }

    if standings.isEmpty { return Verdict(headline: "No data", detail: "Set up Claude Code or Codex") }

    if standings.count == 2, standings[0].rank != standings[1].rank {
        let (better, worse) = standings[0].rank < standings[1].rank ? (standings[0], standings[1]) : (standings[1], standings[0])
        return Verdict(headline: "Use \(better.id.short)", detail: "Until \(worse.backAt.map(clock) ?? "reset") · \(trouble(worse))", use: better.id)
    }

    if standings.allSatisfy({ $0.rank > 0 }) {
        if standings.allSatisfy({ $0.rank == 2 }) {
            let headline = standings.count == 2 ? "Both out" : "\(standings[0].id.short) out"
            return Verdict(headline: headline, detail: "Back \(standings.compactMap(\.backAt).min().map(clock) ?? "soon")")
        }
        return Verdict(headline: "Slow down", detail: standings.map(trouble).joined(separator: " · "))
    }

    let expiring = standings.compactMap { st in
        s.plans.first { $0.id == st.id }?[.weekly].map { (id: st.id, pace: $0.pace(at: now)) }
    }.filter { $0.pace.status == .expiringUnused }
    if let e = expiring.min(by: { ($0.pace.resetsAt ?? .distantFuture) < ($1.pace.resetsAt ?? .distantFuture) }),
       let resets = e.pace.resetsAt {
        return Verdict(headline: "Use \(e.id.short)", detail: "\(percent(e.pace.left)) expires in \(shortDuration(resets.timeIntervalSince(now)))", use: e.id)
    }

    let next = s.plans.compactMap { $0[.fiveHour]?.pace(at: now).resetsAt }.min().map { "next reset \(clock($0))" }
    let either = standings.count == 2 ? "Either works" : nil
    return Verdict(headline: "On pace", detail: [either, next].compactMap { $0 }.joined(separator: " · "))
}

extension Verdict {
    init(headline: String, detail: String) { self.init(headline: headline, detail: detail, use: nil) }
}

// MARK: - Text

public struct Note: Equatable, Sendable {
    public enum Style: Sendable { case plain, strong, pill }
    public var text: String
    public var style: Style
    public init(text: String, style: Style) {
        self.text = text
        self.style = style
    }
}

/// The short note beside a meter: "Out ~11:13", "Resets Mon", "Expires in 4h 39m".
public func note(for w: LimitWindow, at now: Date, timeZone tz: TimeZone = .current) -> Note {
    let p = w.pace(at: now)
    return switch p.status {
    case .reset: Note(text: "Full", style: .plain)
    case .limitReached: Note(text: "Back \(clockTime(w.resetsAt, tz))", style: .pill)
    case .runningOut: Note(text: "Out ~\(p.runout.map { clockTime($0, tz) } ?? "soon")", style: .pill)
    case .expiringUnused: Note(text: "Expires in \(shortDuration(w.resetsAt.timeIntervalSince(now)))", style: .strong)
    case .onPace: Note(text: "Resets \(w.resetsAt.timeIntervalSince(now) < 86400 ? clockTime(w.resetsAt, tz) : format("EEE", w.resetsAt, tz))", style: .plain)
    }
}

/// e.g. "Claude Code 5-hour limit: 38% left, runs out around 11:13".
public func accessibilityLabel(_ id: PlanID, _ w: LimitWindow, at now: Date, timeZone tz: TimeZone = .current) -> String {
    let p = w.pace(at: now)
    let state = switch p.status {
    case .reset: "full"
    case .limitReached: "limit reached, back at \(clockTime(w.resetsAt, tz))"
    case .runningOut: "runs out around \(p.runout.map { clockTime($0, tz) } ?? "soon")"
    case .expiringUnused: "unused quota expires in \(spokenDuration(w.resetsAt.timeIntervalSince(now)))"
    case .onPace: w.resetsAt.timeIntervalSince(now) < 86400 ? "resets at \(clockTime(w.resetsAt, tz))" : "resets \(format("EEEE", w.resetsAt, tz))"
    }
    return "\(id.name) \(w.kind.spoken) limit: \(percent(p.left)) left, \(state)"
}

public struct MenuBarSummary: Equatable, Sendable {
    /// Shown beside the glyph: "38%", "OUT ~11:13", "BACK 12:12", or empty.
    public var text: String
    public var spoken: String
}

public func menuBarSummary(_ s: Snapshot, at now: Date, timeZone tz: TimeZone = .current) -> MenuBarSummary {
    let standings = s.plans.compactMap { Standing($0, at: now) }
    let clock = { clockTime($0, tz) }
    if let out = standings.filter({ $0.rank == 2 }).min(by: { ($0.backAt ?? .distantFuture) < ($1.backAt ?? .distantFuture) }) {
        let back = out.backAt.map(clock) ?? "soon"
        return MenuBarSummary(text: "BACK \(back)", spoken: "Coding quotas: \(out.id.name) limit reached, back at \(back)")
    }
    if let low = standings.filter({ $0.rank == 1 }).min(by: { ($0.outAt ?? .distantFuture) < ($1.outAt ?? .distantFuture) }) {
        let out = low.outAt.map(clock) ?? "soon"
        return MenuBarSummary(text: "OUT ~\(out)", spoken: "Coding quotas: \(low.id.name) runs out around \(out)")
    }
    guard let tightest = s.plans.flatMap({ $0.windows.map { $0.pace(at: now).left } }).min() else {
        return MenuBarSummary(text: "", spoken: "Coding quotas: no data")
    }
    return MenuBarSummary(text: percent(tightest), spoken: "Coding quotas: tightest limit \(Int(tightest.rounded())) percent left")
}

/// "Codex 04:24": how old the numbers are, for Codex (only as fresh as its last run) and for
/// any plan that couldn't update. Live Claude numbers need no timestamp.
public func asOfLine(_ s: Snapshot, timeZone tz: TimeZone = .current) -> String {
    s.plans.filter { $0.id == .codex || $0.problem != nil }
        .compactMap { p in p.asOf.map { "\(p.id.short) \(clockTime($0, tz))" } }
        .joined(separator: " · ")
}

public func percent(_ x: Double) -> String { "\(Int(x.rounded()))%" }

/// 24-hour "HH:mm", as in the mockups.
public func clockTime(_ d: Date, _ tz: TimeZone = .current) -> String { format("HH:mm", d, tz) }

func format(_ pattern: String, _ d: Date, _ tz: TimeZone) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = tz
    f.dateFormat = pattern
    return f.string(from: d)
}

func shortDuration(_ seconds: TimeInterval) -> String {
    let m = Int(seconds / 60)
    return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
}

func spokenDuration(_ seconds: TimeInterval) -> String {
    let m = Int(seconds / 60)
    func unit(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
    if m < 60 { return unit(m, "minute") }
    return m % 60 == 0 ? unit(m / 60, "hour") : "\(unit(m / 60, "hour")) \(unit(m % 60, "minute"))"
}

public struct GlyphRows: Equatable, Sendable {
    public var claude: Int
    public var codex: Int
}

/// Lit dots, out of five, for the menu bar glyph: Claude Code on top, Codex below, from each 5-hour window.
public func glyphRows(_ s: Snapshot, at now: Date) -> GlyphRows {
    func lit(_ p: PlanSnapshot) -> Int { p[.fiveHour].map { Int(($0.pace(at: now).left / 20).rounded()) } ?? 0 }
    return GlyphRows(claude: lit(s.claude), codex: lit(s.codex))
}
