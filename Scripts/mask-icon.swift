// Masks edge-to-edge square artwork into a macOS icon squircle with the
// standard margins (824pt icon on a 1024pt canvas, r=186), transparent
// outside. Usage: swift Scripts/mask-icon.swift <source.png> <output.png>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: mask-icon.swift <source.png> <output.png>")
    exit(1)
}
guard let source = NSImage(contentsOf: URL(fileURLWithPath: arguments[1])) else {
    print("couldn't load \(arguments[1])")
    exit(1)
}

let canvas = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
rep.size = NSSize(width: canvas, height: canvas)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

let iconRect = NSRect(x: 100, y: 100, width: 824, height: 824)
NSBezierPath(roundedRect: iconRect, xRadius: 186, yRadius: 186).addClip()
// The generated artwork carries its own whitespace margins, so draw it
// zoomed past the squircle edges to tighten the crop.
let zoom: CGFloat = 1.28
let drawSize = iconRect.width * zoom
let drawRect = NSRect(
    x: iconRect.midX - drawSize / 2,
    y: iconRect.midY - drawSize / 2,
    width: drawSize,
    height: drawSize
)
source.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: arguments[2]))
print("masked → \(arguments[2])")
