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

enum BackgroundOption: String, AppEnum {
    case `default`, tinted, clear
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Background"
    static let caseDisplayRepresentations: [BackgroundOption: DisplayRepresentation] = [
        .default: "Default", .tinted: "Tinted glass", .clear: "Fully clear",
    ]
    var style: Backdrop { Backdrop(rawValue: rawValue) ?? .global }
}

struct SmallIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Plan"
    @Parameter(title: "Plan", default: .claude) var plan: PlanOption
    @Parameter(title: "Background", default: .default) var background: BackgroundOption
}

struct LayoutIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Headroom"
    @Parameter(title: "Background", default: .default) var background: BackgroundOption
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
                .widgetBackground(e.intent.background.style)
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
            VerdictView(snapshot: e.snapshot, now: e.date).widgetBackground(e.intent.background.style)
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
            LimitsView(snapshot: e.snapshot, now: e.date).widgetBackground(e.intent.background.style)
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
            LargeView(snapshot: e.snapshot, now: e.date).widgetBackground(e.intent.background.style)
        }
        .configurationDisplayName("Headroom")
        .description("Which plan to use, with every limit of both plans.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Background

private struct WidgetBackground: ViewModifier {
    var style: Backdrop
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        switch style {
        case .tinted:
            content.containerBackground(for: .widget) {
                TintedGlass().overlay(ContainerRelativeShape().strokeBorder(.white.opacity(scheme == .dark ? 0.1 : 0.6), lineWidth: 1))
            }
        case .clear:
            content.clearShadow().containerBackground(for: .widget) { Color.clear }
        }
    }
}

extension View {
    func widgetBackground(_ style: Backdrop) -> some View { modifier(WidgetBackground(style: style)) }
}
