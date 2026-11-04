import CoreServices
import Foundation
import HeadroomCore
import Observation
import WidgetKit

/// Reads both plans, keeps the latest snapshot, and hands it to the widgets through the App Group.
@MainActor @Observable
final class Store {
    private(set) var snapshot: Snapshot
    /// Bumped on every refresh so pace and "runs out at" move even when usage doesn't.
    private(set) var now = Date()
    private(set) var refreshing = false

    @ObservationIgnored private var lastClaudeFetch = Date.distantPast
    @ObservationIgnored private var lastWritten: Data?
    @ObservationIgnored private var lastReloaded: Snapshot?
    @ObservationIgnored private var watcher: FolderWatcher?
    private let codex = CodexReader()
    private let claude = ClaudeClient()

    init() {
        snapshot = AppGroup.snapshotURL.flatMap(Snapshot.read)
            ?? Snapshot(claude: PlanSnapshot(id: .claude), codex: PlanSnapshot(id: .codex))
        watcher = FolderWatcher(path: codex.sessions.path) { [weak self] in
            Task { await self?.refresh() }
        }
        Task {
            await refresh(force: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await refresh()
            }
        }
    }

    /// Codex is a local read, so it runs every time. The Claude endpoint isn't ours, so it's
    /// called at most every 5 minutes unless forced.
    func refresh(force: Bool = false) async {
        now = Date()
        let reader = codex
        snapshot.codex = await Task.detached { reader.read() }.value.keepingData(from: snapshot.codex)
        if force || now.timeIntervalSince(lastClaudeFetch) >= 300 {
            lastClaudeFetch = now
            refreshing = true
            snapshot.claude = await claude.fetch().keepingData(from: snapshot.claude)
            refreshing = false
        }
        save()
    }

    private func save() {
        guard let url = AppGroup.snapshotURL, let data = try? JSONEncoder().encode(snapshot), data != lastWritten else { return }
        do {
            try data.write(to: url, options: .atomic)
            lastWritten = data
            if snapshot.forWidgets != lastReloaded {
                lastReloaded = snapshot.forWidgets
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            NSLog("Headroom: couldn't write the widget snapshot: \(error.localizedDescription)")
        }
    }
}

/// Recursive FSEvents watch, so new Codex log lines show up without waiting for the timer.
final class FolderWatcher {
    private final class Box: @unchecked Sendable { let onChange: @MainActor () -> Void; init(_ f: @escaping @MainActor () -> Void) { onChange = f } }
    private var stream: FSEventStreamRef?
    private let box: Box

    init?(path: String, onChange: @escaping @MainActor () -> Void) {
        box = Box(onChange)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(box).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { box.onChange() }
        }
        // 2 s latency coalesces the bursts Codex writes while it streams.
        guard let stream = FSEventStreamCreate(nil, callback, &context, [path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
