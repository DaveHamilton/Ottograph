import AppKit

/// The menu bar glyph: a monochrome, template-image rendition of the Otto
/// mark (open cursive O, exit swoosh, antenna) drawn in code — menu bar
/// icons must be templates so they adapt to dark mode and highlight state,
/// which rules out the full-color app icon artwork.
enum MenuBarIcon {
    static func make() -> NSImage {
        // Prefer the generated template artwork bundled with the app
        // (Assets/nbp-menubar.png → menubar-template.png, 36px = 18pt @2x).
        if let url = Bundle.main.url(forResource: "menubar-template", withExtension: "png"),
           let bundled = NSImage(contentsOf: url) {
            bundled.size = NSSize(width: 18, height: 18)
            bundled.isTemplate = true
            bundled.accessibilityDescription = "Ottograph"
            return bundled
        }
        return drawn()
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
