import AppIntents
import HeadroomCore
import HeadroomUI
import SwiftUI
import WidgetKit

@main
struct HeadroomWidgets: WidgetBundle {
    var body: some Widget {
        SmallWidget()
        VerdictWidget()
        LimitsWidget()
        LargeWidget()
    }
}

// MARK: - Configuration

enum PlanOption: String, AppEnum {
    case claude, codex
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Plan"
    static let caseDisplayRepresentations: [PlanOption: DisplayRepresentation] = [.claude: "Claude Code", .codex: "Codex"]
}

struct SmallIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Plan"
    @Parameter(title: "Plan", default: .claude) var plan: PlanOption
}

struct LayoutIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Headroom"
}

// MARK: - Timeline

struct Entry<Intent: WidgetConfigurationIntent>: TimelineEntry {
    var date: Date
    var snapshot: Snapshot
    var intent: Intent
}

/// Reads the snapshot the app wrote; never touches ~/.codex or the Keychain.
struct Provider<Intent: WidgetConfigurationIntent>: AppIntentTimelineProvider {
    private var stored: Snapshot {
        AppGroup.snapshotURL.flatMap(Snapshot.read) ?? Snapshot(
            claude: PlanSnapshot(id: .claude, problem: .notSetUp("Open Headroom")),
            codex: PlanSnapshot(id: .codex, problem: .notSetUp("Open Headroom")))
    }

    func placeholder(in context: Context) -> Entry<Intent> {
        Entry(date: .now, snapshot: .sample(at: .now), intent: Intent())
    }

    func snapshot(for intent: Intent, in context: Context) async -> Entry<Intent> {
        let s = AppGroup.snapshotURL.flatMap(Snapshot.read)
        return Entry(date: .now, snapshot: s ?? .sample(at: .now), intent: intent)
    }

    func timeline(for intent: Intent, in context: Context) async -> Timeline<Entry<Intent>> {
        let s = stored
        return Timeline(entries: timelineDates(s, from: .now).map { Entry(date: $0, snapshot: s, intent: intent) }, policy: .atEnd)
    }
}

// MARK: - Widgets

struct SmallWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.miguelkalawdev.headroom.small", intent: SmallIntent.self, provider: Provider<SmallIntent>()) { e in
            SmallView(plan: e.intent.plan == .claude ? e.snapshot.claude : e.snapshot.codex, now: e.date)
                .widgetBackground()
        }
        .configurationDisplayName("5-hour limit")
        .description("One plan's 5-hour limit and its even pace.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct VerdictWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.miguelkalawdev.headroom.verdict", intent: LayoutIntent.self, provider: Provider<LayoutIntent>()) { e in
            VerdictView(snapshot: e.snapshot, now: e.date).widgetBackground()
        }
        .configurationDisplayName("Which plan")
        .description("Which plan to use right now, with both 5-hour limits.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct LimitsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.miguelkalawdev.headroom.limits", intent: LayoutIntent.self, provider: Provider<LayoutIntent>()) { e in
            LimitsView(snapshot: e.snapshot, now: e.date).widgetBackground()
        }
        .configurationDisplayName("All limits")
        .description("The 5-hour and weekly limits of both plans.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct LargeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.miguelkalawdev.headroom.large", intent: LayoutIntent.self, provider: Provider<LayoutIntent>()) { e in
            LargeView(snapshot: e.snapshot, now: e.date).widgetBackground()
        }
        .configurationDisplayName("Headroom")
        .description("Which plan to use, with every limit of both plans.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Background

private struct WidgetBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        content.containerBackground(for: .widget) {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                dark ? Color(red: 12 / 255, green: 12 / 255, blue: 12 / 255).opacity(0.46) : Color.white.opacity(0.5)
                ContainerRelativeShape().strokeBorder(.white.opacity(dark ? 0.1 : 0.6), lineWidth: 1)
            }
        }
    }
}

extension View {
    func widgetBackground() -> some View { modifier(WidgetBackground()) }
}
