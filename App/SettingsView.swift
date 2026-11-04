import SwiftUI

struct SettingsView: View {
    @AppStorage("showMenuBarText") private var showText = true

    var body: some View {
        Form {
            Toggle("Show text next to the menu bar icon", isOn: $showText)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}
