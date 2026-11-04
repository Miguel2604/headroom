import HeadroomCore
import SwiftUI
import WidgetKit

struct SettingsView: View {
    @AppStorage("showMenuBarText") private var showText = true
    @AppStorage(Backdrop.key, store: AppGroup.defaults) private var background = Backdrop.tinted
    @AppStorage(DesktopKeys.show) private var desktopPanel = false
    @AppStorage(DesktopKeys.layout) private var layout = DesktopLayout.large
    @AppStorage(DesktopKeys.locked) private var locked = false

    var body: some View {
        Form {
            Toggle("Show text next to the menu bar icon", isOn: $showText)
            Section {
                Picker("Background", selection: $background) {
                    Text("Tinted glass").tag(Backdrop.tinted)
                    Text("Fully clear").tag(Backdrop.clear)
                }
                .onChange(of: background) { WidgetCenter.shared.reloadAllTimelines() }
            } footer: {
                Text("Each widget can override this in its Edit Widget menu.")
            }
            Section {
                Toggle("Show a panel on the desktop", isOn: $desktopPanel)
                Picker("Layout", selection: $layout) {
                    ForEach(DesktopLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(!desktopPanel)
                Toggle("Lock position", isOn: $locked).disabled(!desktopPanel)
            } header: {
                Text("Desktop panel")
            } footer: {
                Text("macOS can dim desktop widgets while you work. The desktop panel is never dimmed and stays fully clear. Unlock it to drag it into place.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}
