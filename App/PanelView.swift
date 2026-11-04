import HeadroomCore
import HeadroomUI
import SwiftUI

/// The panel under the menu bar item: verdict, four meters, actions.
struct PanelView: View {
    @Environment(Store.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let s = store.snapshot, now = store.now
        let v = verdict(s, at: now)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(v.headline.uppercased()).num(30)
                    Text(v.detail).lbl()
                }
                .accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(s.plans, id: \.id) { plan in
                        LimitRow(plan: plan, kind: .fiveHour, now: now)
                        LimitRow(plan: plan, kind: .weekly, now: now)
                    }
                }
                status(s, now: now)
            }
            .padding(EdgeInsets(top: 12, leading: 10, bottom: 14, trailing: 10))

            Separator().padding(.bottom, 6)
            MenuItem("Refresh", shortcut: "⌘R") { Task { await store.refresh(force: true) } }
                .keyboardShortcut("r")
            MenuItem("Open Claude usage") { open("https://claude.ai/settings/usage") }
            MenuItem("Open Codex usage") { open("https://chatgpt.com/codex/settings/usage") }
            Separator().padding(.vertical, 6)
            MenuItem("Settings…", shortcut: "⌘,") {
                NSApp.activate()
                openSettings()
            }
            .keyboardShortcut(",")
            MenuItem("Quit Headroom", shortcut: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(6)
        .frame(width: 312)
    }

    /// Problems first, then how old each plan's numbers are.
    @ViewBuilder private func status(_ s: Snapshot, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(s.plans, id: \.id) { plan in
                if let problem = plan.problem {
                    Text("\(plan.id.short): \(problem.message)").lbl().lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            let ages = asOfLine(s)
            if !ages.isEmpty { Text("As of " + ages).lbl().secondary() }
        }
    }

    private func open(_ url: String) { NSWorkspace.shared.open(URL(string: url)!) }
}

private struct Separator: View {
    var body: some View { Rectangle().fill(.primary.opacity(0.14)).frame(height: 1).padding(.horizontal, 10) }
}

/// A menu-style row: inverts on hover, like the mockup.
private struct MenuItem: View {
    var title: String
    var shortcut: String?
    var action: () -> Void
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme

    init(_ title: String, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).lbl(11.5)
                Spacer()
                if let shortcut { Text(shortcut).font(.fragment(11.5)).opacity(0.6) }
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .contentShape(Rectangle())
            .foregroundStyle(hovered ? (scheme == .dark ? Color.black : .white) : .primary)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovered ? Color.primary : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
