import AppKit
import HeadroomCore
import HeadroomUI
import SwiftUI
import Testing

/// Renders every layout and state. Set HEADROOM_RENDER_DIR to also write them out as PNGs.
@MainActor @Suite struct RenderTests {
    let now = Date()

    @discardableResult
    func render(_ name: String, _ view: some View, width: CGFloat, height: CGFloat, dark: Bool = true) -> NSImage? {
        let card = view
            .frame(width: width, height: height)
            .background(dark ? Color(white: 0.17) : Color(white: 0.88))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(16)
            .background(dark ? Color(white: 0.32) : Color(white: 0.72))
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        if let dir = ProcessInfo.processInfo.environment["HEADROOM_RENDER_DIR"],
           let tiff = renderer.nsImage?.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(filePath: dir).appending(path: "\(name)-\(dark ? "dark" : "light").png"))
        }
        return renderer.nsImage
    }

    @Test func layouts() {
        let s = Snapshot.sample(at: now)
        for dark in [true, false] {
            #expect(render("small", SmallView(plan: s.claude, now: now), width: 170, height: 170, dark: dark) != nil)
            #expect(render("verdict", VerdictView(snapshot: s, now: now), width: 364, height: 170, dark: dark) != nil)
            #expect(render("limits", LimitsView(snapshot: s, now: now), width: 364, height: 170, dark: dark) != nil)
            #expect(render("large", LargeView(snapshot: s, now: now), width: 364, height: 382, dark: dark) != nil)
        }
    }

    @Test func smallStates() {
        let s = Snapshot.sample(at: now)
        var reached = s.claude
        reached.windows[0].usedPercent = 100
        var failed = s.codex
        failed.problem = .failed("Offline")
        let states: [(String, PlanSnapshot)] = [
            ("on-pace", s.codex),
            ("running-out", s.claude),
            ("limit-reached", reached),
            ("couldnt-update", failed),
            ("not-set-up", PlanSnapshot(id: .codex, problem: .notSetUp("Run Codex once to see its limits"))),
        ]
        for (name, plan) in states {
            #expect(render("state-\(name)", SmallView(plan: plan, now: now), width: 170, height: 170) != nil)
        }
        var expiring = s.codex
        expiring.windows[0] = LimitWindow(kind: .fiveHour, usedPercent: 30, resetsAt: now + 20 * 60)
        #expect(render("state-expiring", SmallView(plan: expiring, now: now), width: 170, height: 170) != nil)
        let missing = Snapshot(claude: s.claude, codex: PlanSnapshot(id: .codex, problem: .notSetUp("Run Codex once to see its limits")))
        #expect(render("large-missing", LargeView(snapshot: missing, now: now), width: 364, height: 382) != nil)
    }
}
