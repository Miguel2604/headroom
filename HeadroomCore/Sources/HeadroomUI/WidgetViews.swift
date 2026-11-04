import HeadroomCore
import SwiftUI

/// Opens the app and forces a refresh. The widget can't fetch anything itself: it's sandboxed.
public let refreshURL = URL(string: "headroom://refresh")!

/// Small, 170×170: one plan's 5-hour limit.
public struct SmallView: View {
    var plan: PlanSnapshot
    var now: Date

    public init(plan: PlanSnapshot, now: Date) {
        self.plan = plan
        self.now = now
    }

    public var body: some View {
        let window = plan[.fiveHour]
        let pace = window?.pace(at: now)
        let reached = pace?.status == .limitReached
        VStack(alignment: .leading, spacing: 0) {
            Text(reached ? "\(plan.id.short) · back at" : "\(plan.id.short) · 5h").lbl().secondary()
            Spacer(minLength: 0)
            Group {
                if let window, reached {
                    Text(clockTime(window.resetsAt)).num(42).frame(height: 50, alignment: .leading)
                } else {
                    Text(pace.map { percent($0.left) } ?? "--").num(50).frame(height: 50, alignment: .leading)
                }
                DotMeter(pace, count: 14, size: 7).padding(.top, 12)
            }
            .opacity(plan.problem == nil ? 1 : 0.4)
            HStack(spacing: 0) { footer(window, reached: reached) }
                .frame(height: 18)
                .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel(plan, .fiveHour, now: now))
    }

    @ViewBuilder private func footer(_ window: LimitWindow?, reached: Bool) -> some View {
        switch plan.problem {
        case .notSetUp?:
            Text("Not set up").lbl().secondary()
        case .failed?:
            Text(plan.asOf.map { "As of \(clockTime($0))" } ?? "Couldn't update").lbl().secondary()
            Spacer(minLength: 4)
            RetryButton()
        case nil:
            if reached { NoteView(Note(text: "Limit reached", style: .pill)) }
            else if let window { NoteView(note(for: window, at: now)) }
        }
    }
}

public struct RetryButton: View {
    public init() {}
    public var body: some View {
        Link(destination: refreshURL) {
            Text("Retry").lbl()
                .padding(.horizontal, 7).padding(.vertical, 2)
                .overlay(Capsule().strokeBorder(lineWidth: 1))
        }
        .accessibilityLabel("Retry")
    }
}

/// Medium, 364×170: the verdict and both 5-hour meters.
public struct VerdictView: View {
    var snapshot: Snapshot
    var now: Date

    public init(snapshot: Snapshot, now: Date) {
        self.snapshot = snapshot
        self.now = now
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VerdictText(snapshot: snapshot, now: now, size: 34, gap: 7)
            Spacer(minLength: 0)
            HStack(spacing: 24) {
                ForEach(snapshot.plans, id: \.id) { plan in
                    let pace = plan[.fiveHour]?.pace(at: now)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(plan.id.short) 5h").lbl().secondary()
                            Spacer(minLength: 0)
                            Text(pace.map { percent($0.left) } ?? "--").num(17)
                        }
                        DotMeter(pace, count: 12, size: 7)
                    }
                    .opacity(plan.problem == nil ? 1 : 0.4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spokenLabel(plan, .fiveHour, now: now))
                }
            }
        }
        .padding(.vertical, 18).padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Medium, 364×170: all four meters.
public struct LimitsView: View {
    var snapshot: Snapshot
    var now: Date

    public init(snapshot: Snapshot, now: Date) {
        self.snapshot = snapshot
        self.now = now
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Coding quotas").lbl().secondary().accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text(asOfLine(snapshot)).lbl().secondary()
            }
            ForEach(snapshot.plans, id: \.id) { plan in
                Spacer(minLength: 0)
                LimitRow(plan: plan, kind: .fiveHour, now: now, labelWidth: 92)
                Spacer(minLength: 0)
                LimitRow(plan: plan, kind: .weekly, now: now, labelWidth: 92)
            }
        }
        .padding(.vertical, 18).padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Large, 364×382: the verdict plus both plans and both windows.
public struct LargeView: View {
    var snapshot: Snapshot
    var now: Date

    public init(snapshot: Snapshot, now: Date) {
        self.snapshot = snapshot
        self.now = now
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VerdictText(snapshot: snapshot, now: now, size: 38, gap: 8)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(snapshot.plans, id: \.id) { plan in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(plan.tier.map { "\(plan.id.name) — \($0)" } ?? plan.id.name).lbl().secondary()
                        ForEach([WindowKind.fiveHour, .weekly], id: \.self) { kind in
                            window(plan, kind)
                        }
                    }
                }
            }
            .padding(.top, 22)
            Spacer(minLength: 0)
            HStack {
                HStack(spacing: 6) {
                    Circle().strokeBorder(lineWidth: 1.5).frame(width: 8, height: 8)
                    Text("Even pace").lbl()
                }
                .secondary()
                .accessibilityHidden(true)
                Spacer(minLength: 0)
                Text(asOfLine(snapshot)).lbl().secondary()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func window(_ plan: PlanSnapshot, _ kind: WindowKind) -> some View {
        let w = plan[kind]
        let pace = w?.pace(at: now)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                HStack(spacing: 8) {
                    Text(kind.label).lbl()
                    if let w, plan.problem == nil { NoteView(note(for: w, at: now)) }
                    else if let problem = plan.problem { Text(problem.message).lbl().secondary() }
                }
                Spacer(minLength: 0)
                Text(pace.map { percent($0.left) } ?? "--").num(20)
            }
            .frame(height: 20)
            DotMeter(pace, count: 24, size: 8)
        }
        .opacity(plan.problem == nil ? 1 : 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel(plan, kind, now: now))
    }
}

/// The headline and its one-line reason.
struct VerdictText: View {
    var snapshot: Snapshot
    var now: Date
    var size: CGFloat
    var gap: CGFloat

    var body: some View {
        let v = verdict(snapshot, at: now)
        VStack(alignment: .leading, spacing: gap) {
            Text(v.headline.uppercased()).num(size).accessibilityAddTraits(.isHeader)
            Text(v.detail).lbl()
        }
        .accessibilityElement(children: .combine)
    }
}

extension Snapshot {
    /// The mockups' numbers, for the widget gallery and placeholders.
    public static func sample(at now: Date) -> Snapshot {
        Snapshot(
            claude: PlanSnapshot(id: .claude, tier: "Max", windows: [
                LimitWindow(kind: .fiveHour, usedPercent: 62, resetsAt: now + 151 * 60),
                LimitWindow(kind: .weekly, usedPercent: 26, resetsAt: now + 119 * 3600),
            ], asOf: now),
            codex: PlanSnapshot(id: .codex, tier: "Plus", windows: [
                LimitWindow(kind: .fiveHour, usedPercent: 23, resetsAt: now + 192 * 60),
                LimitWindow(kind: .weekly, usedPercent: 57, resetsAt: now + 279 * 60),
            ], asOf: now))
    }
}
