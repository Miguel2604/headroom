import Foundation

public struct Pace: Equatable, Sendable {
    public enum Status: Sendable { case onPace, runningOut, limitReached, expiringUnused, reset }

    /// Percent of the limit left, 0...100.
    public var left: Double
    /// Percent an even rate would leave now: where the hollow pace dot goes.
    public var evenLeft: Double
    /// When the current rate uses up what's left. Nil if nothing has been used.
    public var runout: Date?
    /// Nil once the window has reset and no newer data has arrived.
    public var resetsAt: Date?
    public var status: Status
}

extension LimitWindow {
    public func pace(at now: Date) -> Pace {
        let window = minutes * 60
        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 0 else { return Pace(left: 100, evenLeft: 100, runout: nil, resetsAt: nil, status: .reset) }

        let elapsed = min(max(1 - remaining / window, 0), 1)
        let used = min(max(usedPercent, 0), 100)
        let left = 100 - used
        let evenLeft = 100 * (1 - elapsed)
        let elapsedTime = elapsed * window
        let runout = used > 0 && elapsedTime > 0 ? now + left / (used / elapsedTime) : nil

        let status: Pace.Status =
            if left <= 0 { .limitReached }
            else if left < evenLeft - 5, let runout, runout < resetsAt { .runningOut }
            else if elapsed > 0.9, left > 25 { .expiringUnused }
            else { .onPace }
        return Pace(left: left, evenLeft: evenLeft, runout: runout, resetsAt: resetsAt, status: status)
    }
}

public enum Dot: Sendable { case on, off, pace }

/// Lit dots show what's left, off dots what's used, and one hollow dot marks even pace.
public func dots(left: Double, evenLeft: Double, count n: Int) -> [Dot] {
    let on = Int((left / 100 * Double(n)).rounded())
    let pace = max(1, Int((evenLeft / 100 * Double(n)).rounded()))
    return (0..<n).map { $0 == pace - 1 ? .pace : $0 < on ? .on : .off }
}

/// Widget timeline: an entry every 5 minutes for the next hour, because even pace and
/// "runs out at" move with time. Entries stop at the next reset, which gets its own entry.
public func timelineDates(_ s: Snapshot, from now: Date) -> [Date] {
    let nextReset = s.plans.flatMap(\.windows).map(\.resetsAt).filter { $0 > now }.min()
    let end = min(now + 3600, nextReset ?? .distantFuture)
    let steps = stride(from: now, to: end, by: 300).map { $0 }
    return end == nextReset ? steps + [end] : steps
}
