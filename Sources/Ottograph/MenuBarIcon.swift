import AppKit

/// The menu bar glyph: a monochrome, template-image rendition of the Otto
/// mark (open cursive O, exit swoosh, antenna) drawn in code — menu bar
/// icons must be templates so they adapt to dark mode and highlight state,
/// which rules out the full-color app icon artwork.
enum MenuBarIcon {
    /// - Parameter paused: when true, the glyph is struck through, so a
    ///   paused Ottograph doesn't look identical to a working one.
    static func make(paused: Bool = false) -> NSImage {
        let base = bundledGlyph() ?? drawn()
        let image = paused ? struckThrough(base) : base
        image.isTemplate = true
        image.accessibilityDescription = paused ? "Ottograph (paused)" : "Ottograph"
        return image
    }

    /// The generated template artwork bundled with the app
    /// (Assets/nbp-menubar.png → menubar-template.png, 36px = 18pt @2x).
    private static func bundledGlyph() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "menubar-template", withExtension: "png"),
              let bundled = NSImage(contentsOf: url) else { return nil }
        bundled.size = NSSize(width: 18, height: 18)
        return bundled
    }

    /// Draws the glyph with a diagonal strike through it. The strike is
    /// knocked out of the glyph with a small transparent gap on either
    /// side, so the two shapes read as separate rather than merging into
    /// one blob at menu bar size.
    private static func struckThrough(_ base: NSImage) -> NSImage {
        NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)

            let start = NSPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.18)
            let end = NSPoint(x: rect.maxX - rect.width * 0.16, y: rect.maxY - rect.height * 0.18)
            let strike = NSBezierPath()
            strike.move(to: start)
            strike.line(to: end)
            strike.lineCapStyle = .round

            // Clear a slightly wider channel first, then stroke into it.
            NSGraphicsContext.current?.compositingOperation = .clear
            strike.lineWidth = rect.width * 0.21
            strike.stroke()

            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setStroke()
            strike.lineWidth = rect.width * 0.1
            strike.stroke()
            return true
        }
    }

    /// Code-drawn fallback for bare `swift run` builds with no bundle.
    private static func drawn() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // O loop, open at the lower right (gap ~305°–355°)
            let loop = NSBezierPath()
            loop.appendArc(withCenter: NSPoint(x: 8.0, y: 8.2), radius: 4.9,
                           startAngle: 355, endAngle: 305, clockwise: false)
            loop.lineWidth = 1.8
            loop.lineCapStyle = .round
            loop.stroke()

            // exit tail: one smooth swoosh rightward
            let tailStart = NSPoint(x: 8.0 + 4.9 * cos(305 * .pi / 180),
                                    y: 8.2 + 4.9 * sin(305 * .pi / 180))
            let tail = NSBezierPath()
            tail.move(to: tailStart)
            tail.curve(to: NSPoint(x: 16.4, y: 6.4),
                       controlPoint1: NSPoint(x: 12.2, y: 2.6),
                       controlPoint2: NSPoint(x: 15.0, y: 4.2))
            tail.lineWidth = 1.7
            tail.lineCapStyle = .round
            tail.stroke()

            // antenna stem + knob
            let stem = NSBezierPath()
            stem.move(to: NSPoint(x: 8.0, y: 13.1))
            stem.line(to: NSPoint(x: 8.0, y: 14.9))
            stem.lineWidth = 1.5
            stem.lineCapStyle = .round
            stem.stroke()
            NSBezierPath(ovalIn: NSRect(x: 8.0 - 1.4, y: 15.1, width: 2.8, height: 2.8)).fill()

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Ottograph"
        return image
    }
}
