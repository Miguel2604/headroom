import HeadroomCore
import SwiftUI

@main
struct HeadroomApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @AppStorage("showMenuBarText") private var showText = true

    var body: some Scene {
        let store = delegate.store
        MenuBarExtra {
            PanelView().environment(store)
        } label: {
            let summary = menuBarSummary(store.snapshot, at: store.now)
            Image(nsImage: MenuBarIcon.image(glyphRows(store.snapshot, at: store.now), text: showText ? summary.text : ""))
                .accessibilityLabel(summary.spoken)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    private var desktopPanel: DesktopPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        desktopPanel = DesktopPanel(store: store)
    }

    /// headroom://refresh, from a widget's Retry button.
    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.host == "refresh" }) {
            Task { await store.refresh(force: true) }
        }
    }
}
