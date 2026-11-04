import AppKit
import HeadroomCore
import HeadroomUI

/// Two rows of five dots (Claude Code on top, Codex below) plus optional text, drawn as a
/// template image so macOS tints it like every other menu bar item.
enum MenuBarIcon {
    static func image(_ rows: GlyphRows, text: String) -> NSImage {
        Fonts.register()
        let dot: CGFloat = 2.4, gapX: CGFloat = 1, gapY: CGFloat = 1.4, height: CGFloat = 16
        let glyphWidth = 5 * dot + 4 * gapX
        let label = NSAttributedString(string: text, attributes: [
            .font: NSFont(name: "FragmentMono-Regular", size: 12) ?? .monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.black,
        ])
        let textWidth = text.isEmpty ? 0 : ceil(label.size().width) + 6
        let image = NSImage(size: NSSize(width: glyphWidth + textWidth, height: height), flipped: false) { _ in
            let top = (height + 2 * dot + gapY) / 2
            for (row, lit) in [rows.claude, rows.codex].enumerated() {
                for i in 0..<5 {
                    NSColor.black.withAlphaComponent(i < lit ? 1 : 0.3).setFill()
                    let x = CGFloat(i) * (dot + gapX), y = top - dot - CGFloat(row) * (dot + gapY)
                    NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dot, height: dot)).fill()
                }
            }
            if !text.isEmpty {
                label.draw(at: NSPoint(x: glyphWidth + 6, y: (height - label.size().height) / 2))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
