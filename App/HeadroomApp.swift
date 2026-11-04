import HeadroomCore
import SwiftUI

@main
struct HeadroomApp: App {
    @State private var store = Store()
    @AppStorage("showMenuBarText") private var showText = true

    var body: some Scene {
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
