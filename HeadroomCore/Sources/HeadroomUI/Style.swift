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

    public init(_ pace: Pace, count: Int, size: CGFloat) {
        dots = HeadroomCore.dots(left: pace.left, evenLeft: pace.evenLeft, count: count)
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
    var plan: PlanID
    var window: LimitWindow
    var now: Date
    var labelWidth: CGFloat
    var dotCount: Int

    public init(plan: PlanID, window: LimitWindow, now: Date, labelWidth: CGFloat = 88, dotCount: Int = 16) {
        self.plan = plan
        self.window = window
        self.now = now
        self.labelWidth = labelWidth
        self.dotCount = dotCount
    }

    public var body: some View {
        let pace = window.pace(at: now)
        let risky = note(for: window, at: now).style == .pill
        HStack(spacing: 12) {
            Text("\(plan.short) \(window.kind.label)").lbl()
                .opacity(risky ? 1 : 0.68)
                .frame(width: labelWidth, alignment: .leading)
            DotMeter(pace, count: dotCount, size: 6)
            Text(percent(pace.left)).num(17).frame(width: 46, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HeadroomCore.accessibilityLabel(plan, window, at: now))
    }
}
