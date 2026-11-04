import Foundation

public enum PlanID: String, Codable, CaseIterable, Sendable {
    case claude, codex
    public var name: String { self == .claude ? "Claude Code" : "Codex" }
    public var short: String { self == .claude ? "Claude" : "Codex" }
}

public enum WindowKind: String, Codable, Sendable {
    case fiveHour, weekly
    public var label: String { self == .fiveHour ? "5h" : "Week" }
    var spoken: String { self == .fiveHour ? "5-hour" : "weekly" }
    var defaultMinutes: Double { self == .fiveHour ? 300 : 10080 }
}

public struct LimitWindow: Codable, Equatable, Sendable {
    public var kind: WindowKind
    public var usedPercent: Double
    public var resetsAt: Date
    public var minutes: Double

    public init(kind: WindowKind, usedPercent: Double, resetsAt: Date, minutes: Double? = nil) {
        self.kind = kind
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.minutes = minutes ?? kind.defaultMinutes
    }
}

public enum Problem: Codable, Equatable, Sendable {
    /// No data source on this Mac (not installed, not signed in, never run).
    case notSetUp(String)
    /// The source exists but the last read failed. Last good numbers are kept.
    case failed(String)

    public var message: String {
        switch self { case .notSetUp(let m), .failed(let m): m }
    }
}

public struct PlanSnapshot: Codable, Equatable, Sendable {
    public var id: PlanID
    public var tier: String?
    /// 5-hour first, then weekly. Empty when there is no data.
    public var windows: [LimitWindow]
    /// When the numbers were observed.
    public var asOf: Date?
    public var problem: Problem?

    public init(id: PlanID, tier: String? = nil, windows: [LimitWindow] = [], asOf: Date? = nil, problem: Problem? = nil) {
        self.id = id
        self.tier = tier
        self.windows = windows
        self.asOf = asOf
        self.problem = problem
    }

    public subscript(kind: WindowKind) -> LimitWindow? { windows.first { $0.kind == kind } }

    /// A failed read keeps showing the previous numbers, marked by its problem.
    public func keepingData(from previous: PlanSnapshot?) -> PlanSnapshot {
        guard case .failed = problem, windows.isEmpty, let previous else { return self }
        return PlanSnapshot(id: id, tier: previous.tier, windows: previous.windows, asOf: previous.asOf, problem: problem)
    }
}

public struct Snapshot: Codable, Equatable, Sendable {
    public var claude: PlanSnapshot
    public var codex: PlanSnapshot

    public init(claude: PlanSnapshot, codex: PlanSnapshot) {
        self.claude = claude
        self.codex = codex
    }

    public var plans: [PlanSnapshot] { [claude, codex] }

    public static func read(from url: URL) -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    public func write(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}

/// Shared between the app and the widget extension.
public enum AppGroup {
    public static let id = "ZVM726QTBU.com.miguelkalawdev.headroom"
    public static var container: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) }
    public static var snapshotURL: URL? { container?.appending(path: "snapshot.json") }
    public static var defaults: UserDefaults? { UserDefaults(suiteName: id) }
}

/// Tinted glass, or no fill at all with a soft shadow behind the content.
public enum Backdrop: String, Codable, CaseIterable, Sendable {
    case tinted, clear
    public static let key = "background"
    /// The global choice, set in Settings. Each widget can override it.
    public static var global: Backdrop {
        AppGroup.defaults?.string(forKey: key).flatMap(Backdrop.init) ?? .tinted
    }
}
