// Renders Assets/icon.svg to the PNG sizes an .iconset needs.
// Usage: swift Scripts/render-icon.swift <icon.svg> <output-dir>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: render-icon.swift <icon.svg> <output-dir>")
    exit(1)
}
let svgURL = URL(fileURLWithPath: arguments[1])
let outDir = URL(fileURLWithPath: arguments[2])
guard let image = NSImage(contentsOf: svgURL) else {
    print("couldn't load \(svgURL.path)")
    exit(1)
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for (name, pixels) in sizes {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { continue }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
               from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: outDir.appendingPathComponent("\(name).png"))
}
print("rendered \(sizes.count) sizes to \(outDir.path)")
