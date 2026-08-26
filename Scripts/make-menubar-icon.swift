// Converts black-on-white glyph artwork into a macOS menu bar template
// image: auto-crops to the glyph, scales into a 36x36 canvas (18pt @2x),
// and maps darkness to alpha (transparent background, black glyph).
// Usage: swift Scripts/make-menubar-icon.swift <source.png> <dest.png>
import AppKit

guard CommandLine.arguments.count == 3 else {
    print("usage: make-menubar-icon.swift <source.png> <dest.png>")
    exit(1)
}
guard let source = NSImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])) else {
    print("couldn't load source")
    exit(1)
}

// 1. Rasterize the source onto white at a working resolution.
let work = 1024
guard let workRep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: work, pixelsHigh: work,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
workRep.size = NSSize(width: work, height: work)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: workRep)
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: work, height: work).fill()
source.draw(in: NSRect(x: 0, y: 0, width: work, height: work),
            from: .zero, operation: .sourceOver, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

// 2. Bounding box of dark pixels (bitmap rows are top-down).
guard let data = workRep.bitmapData else { exit(1) }
let rowBytes = workRep.bytesPerRow
func luminance(_ x: Int, _ y: Int) -> Int {
    let p = data + y * rowBytes + x * 4
    return (299 * Int(p[0]) + 587 * Int(p[1]) + 114 * Int(p[2])) / 1000
}
var minX = work, minY = work, maxX = -1, maxY = -1
for y in 0..<work {
    for x in 0..<work where luminance(x, y) < 200 {
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
guard maxX >= 0 else { print("no glyph found"); exit(1) }
let bboxW = maxX - minX + 1
let bboxH = maxY - minY + 1
// convert top-down bbox to the bottom-up coords NSImage drawing uses
let fromRect = NSRect(x: CGFloat(minX), y: CGFloat(work - maxY - 1),
                      width: CGFloat(bboxW), height: CGFloat(bboxH))
let workImage = NSImage(size: NSSize(width: work, height: work))
workImage.addRepresentation(workRep)

// 3. Draw the cropped glyph centered into 36x36 (content box 32px).
let target = 36
guard let outRep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: target, pixelsHigh: target,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
outRep.size = NSSize(width: target, height: target)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: outRep)
NSGraphicsContext.current?.imageInterpolation = .high
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: target, height: target).fill()
let fit = 32.0 / CGFloat(max(bboxW, bboxH))
let drawW = CGFloat(bboxW) * fit
let drawH = CGFloat(bboxH) * fit
workImage.draw(in: NSRect(x: (CGFloat(target) - drawW) / 2,
                          y: (CGFloat(target) - drawH) / 2,
                          width: drawW, height: drawH),
               from: fromRect, operation: .sourceOver, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

// 4. Darkness → alpha, color → black.
guard let outData = outRep.bitmapData else { exit(1) }
let outRow = outRep.bytesPerRow
for y in 0..<target {
    for x in 0..<target {
        let p = outData + y * outRow + x * 4
        let lum = (299 * Int(p[0]) + 587 * Int(p[1]) + 114 * Int(p[2])) / 1000
        let alpha = UInt8(clamping: 255 - lum)
        p[0] = 0; p[1] = 0; p[2] = 0; p[3] = alpha
    }
}

guard let png = outRep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print("menu bar template → \(CommandLine.arguments[2])")
