import CoreText
import HeadroomCore
import SwiftUI

public enum Fonts {
    private static let registered: Void = {
        for url in Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    /// Safe to call from anywhere, any number of times.
    public static func register() { _ = registered }
}

extension Font {
    /// Doto Black, for numbers and the verdict.
    public static func doto(_ size: CGFloat) -> Font {
        Fonts.register()
        return .custom("Doto-Black", fixedSize: size)
    }

    public static func fragment(_ size: CGFloat) -> Font {
        Fonts.register()
        return .custom("FragmentMono-Regular", fixedSize: size)
    }
}

extension View {
    public func num(_ size: CGFloat) -> some View { font(.doto(size)).lineLimit(1).minimumScaleFactor(0.5) }

    /// Fragment Mono, uppercase, 0.06em tracking.
    public func lbl(_ size: CGFloat = 11) -> some View {
        font(.fragment(size)).tracking(size * 0.06).textCase(.uppercase).lineLimit(1)
    }

    /// Ink at the secondary-text opacity for the current appearance.
    public func secondary() -> some View { modifier(Secondary()) }
}

private struct Secondary: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View { content.opacity(scheme == .dark ? 0.68 : 0.62) }
}

/// Lit dots = left, off dots = used, the hollow dot = even pace.
public struct DotMeter: View {
    var dots: [Dot]
    var size: CGFloat
    @Environment(\.colorScheme) private var scheme

    /// No pace (no data) draws every dot off.
    public init(_ pace: Pace?, count: Int, size: CGFloat) {
        dots = pace.map { HeadroomCore.dots(left: $0.left, evenLeft: $0.evenLeft, count: count) } ?? Array(repeating: .off, count: count)
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(dots.enumerated()), id: \.offset) { i, dot in
                if i > 0 { Spacer(minLength: 1) }
                Group {
                    switch dot {
                    case .on: Circle()
                    case .off: Circle().opacity(scheme == .dark ? 0.22 : 0.16)
                    case .pace: Circle().strokeBorder(lineWidth: 1.5)
                    }
                }
                .frame(width: size, height: size)
            }
        }
    }
}

/// A meter's note: plain, full-strength, or an inverted pill for warnings.
public struct NoteView: View {
    var note: Note
    @Environment(\.colorScheme) private var scheme

    public init(_ note: Note) { self.note = note }

    public var body: some View {
        switch note.style {
        case .plain: Text(note.text).lbl().secondary()
        case .strong: Text(note.text).lbl()
        case .pill:
            Text(note.text).lbl()
                .foregroundStyle(scheme == .dark ? Color.black : .white)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(scheme == .dark ? Color.white : .black))
        }
    }
}

/// "CLAUDE 5H  ●●●●○○  38%", as in the menu and the all-limits widget.
public struct LimitRow: View {
    var plan: PlanSnapshot
    var kind: WindowKind
    var now: Date
    var labelWidth: CGFloat

    public init(plan: PlanSnapshot, kind: WindowKind, now: Date, labelWidth: CGFloat = 88) {
        self.plan = plan
        self.kind = kind
        self.now = now
        self.labelWidth = labelWidth
    }

    public var body: some View {
        let window = plan[kind]
        let pace = window?.pace(at: now)
        let risky = window.map { note(for: $0, at: now).style == .pill } ?? false
        HStack(spacing: 12) {
            Text("\(plan.id.short) \(kind.label)").lbl()
                .opacity(risky ? 1 : 0.68)
                .frame(width: labelWidth, alignment: .leading)
            DotMeter(pace, count: 16, size: 6)
            Text(pace.map { percent($0.left) } ?? "--").num(17).frame(width: 46, alignment: .trailing)
        }
        .opacity(plan.problem == nil ? 1 : 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel(plan, kind, now: now))
    }
}

/// The meter's VoiceOver label, including why it's dimmed.
public func spokenLabel(_ plan: PlanSnapshot, _ kind: WindowKind, now: Date) -> String {
    let base = plan[kind].map { HeadroomCore.accessibilityLabel(plan.id, $0, at: now) } ?? "\(plan.id.name) \(kind.label) limit: no data"
    return plan.problem.map { "\(base). \($0.message)" } ?? base
}

/// The tinted-glass fill: a dark or light translucent layer over a blur.
public struct TintedGlass: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var solid
    public init() {}
    public var body: some View {
        if solid {
            scheme == .dark ? Color(white: 0.11) : Color(white: 0.95)
        } else {
            glass
        }
    }

    private var glass: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            scheme == .dark ? Color(red: 12 / 255, green: 12 / 255, blue: 12 / 255).opacity(0.46) : Color.white.opacity(0.5)
        }
    }
}

extension View {
    /// The fully clear look: no fill, a soft shadow behind the content for legibility.
    public func clearShadow() -> some View { modifier(ClearShadow()) }
}

private struct ClearShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.shadow(color: scheme == .dark ? .black.opacity(0.55) : .white.opacity(0.7), radius: 8, y: 1)
    }
}
