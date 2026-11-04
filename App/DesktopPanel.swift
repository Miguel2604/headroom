import AppKit
import HeadroomCore
import HeadroomUI
import SwiftUI

/// Desktop Panel mode: the widget layouts in a borderless, transparent window just above the
/// wallpaper, on every Space. Unlike a WidgetKit widget, macOS never dims it or adds a backing.
enum DesktopLayout: String, CaseIterable {
    case large, verdict, limits, claude, codex

    var title: String {
        switch self {
        case .large: "Large"
        case .verdict: "Medium, verdict"
        case .limits: "Medium, all limits"
        case .claude: "Small, Claude Code"
        case .codex: "Small, Codex"
        }
    }

    var size: CGSize {
        switch self {
        case .large: CGSize(width: 364, height: 382)
        case .verdict, .limits: CGSize(width: 364, height: 170)
        case .claude, .codex: CGSize(width: 170, height: 170)
        }
    }
}

enum DesktopKeys {
    static let show = "desktopPanel"
    static let layout = "desktopPanelLayout"
    static let locked = "desktopPanelLocked"
}

@MainActor
final class DesktopPanel {
    private let store: Store
    private var panel: NSPanel?
    private var observer: NSObjectProtocol?

    init(store: Store) {
        self.store = store
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        sync()
    }

    private func sync() {
        let d = UserDefaults.standard
        guard d.bool(forKey: DesktopKeys.show) else {
            panel?.orderOut(nil)
            panel = nil
            return
        }
        let layout = d.string(forKey: DesktopKeys.layout).flatMap(DesktopLayout.init) ?? .large
        let locked = d.bool(forKey: DesktopKeys.locked)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if panel.frame.size != layout.size {
            panel.setContentSize(layout.size)
            panel.contentView = DraggableHostingView(rootView: DesktopContent(layout: layout).environment(store))
        }
        // Locked: clicks go through to the desktop. Unlocked: drag it anywhere.
        panel.ignoresMouseEvents = locked
        panel.orderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 80, y: 300, width: 1, height: 1),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.setFrameAutosaveName("HeadroomDesktopPanel")
        return panel
    }
}

private final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

private struct DesktopContent: View {
    var layout: DesktopLayout
    @Environment(Store.self) private var store
    @AppStorage(Backdrop.key, store: AppGroup.defaults) private var backdrop = Backdrop.tinted
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = store.snapshot, now = store.now
        let shape = RoundedRectangle(cornerRadius: 24)
        Group {
            switch layout {
            case .large: LargeView(snapshot: s, now: now)
            case .verdict: VerdictView(snapshot: s, now: now)
            case .limits: LimitsView(snapshot: s, now: now)
            case .claude: SmallView(plan: s.claude, now: now)
            case .codex: SmallView(plan: s.codex, now: now)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .modifier(BackdropModifier(style: backdrop, shape: shape))
    }
}

private struct BackdropModifier<S: InsettableShape>: ViewModifier {
    var style: Backdrop
    var shape: S
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        switch style {
        case .tinted:
            content.background(TintedGlass().clipShape(shape).overlay(shape.strokeBorder(.white.opacity(scheme == .dark ? 0.1 : 0.6), lineWidth: 1)))
        case .clear:
            content.clearShadow()
        }
    }
}
