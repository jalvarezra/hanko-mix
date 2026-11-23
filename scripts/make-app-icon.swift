// Builds a clean macOS app icon from the Hanko artwork.
// Usage: swift scripts/make-app-icon.swift <source.png> <output-dir>
// (The Hanko artwork lives in App/Branding/, which is kept out of the repo.)
// Crops inside the artwork's tile (dropping its noisy cut-out edge), applies the
// standard macOS icon grid (824 px rounded tile on a 1024 canvas) with a soft
// shadow, and writes AppIcon.iconset + AppIcon.icns + AppIcon-1024.png.
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let source = NSImage(contentsOfFile: args[1]),
      let rep = NSBitmapImageRep(data: source.tiffRepresentation!) else {
    print("usage: make-app-icon.swift <source.png> <output-dir>"); exit(64)
}
let outDir = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// 1. Find the cream tile in the artwork.
let w = rep.pixelsWide, h = rep.pixelsHigh
func isCream(_ x: Int, _ y: Int) -> Bool {
    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
    return c.alphaComponent > 0.95 && c.redComponent > 0.9 && c.greenComponent > 0.85 && c.blueComponent > 0.78
}
func rowRatio(_ y: Int) -> Double { Double((w/4..<3*w/4).filter { isCream($0, y) }.count) / Double(w/2) }
func colRatio(_ x: Int) -> Double { Double((h/4..<3*h/4).filter { isCream(x, $0) }.count) / Double(h/2) }
let top = (0..<h).first { rowRatio($0) > 0.4 }!, bottom = (0..<h).last { rowRatio($0) > 0.4 }!
let left = (0..<w).first { colRatio($0) > 0.4 }!, right = (0..<w).last { colRatio($0) > 0.4 }!
let inset = 12.0
let side = Double(min(right - left, bottom - top)) - 2 * inset
let cx = Double(left + right) / 2, cy = Double(top + bottom) / 2
// Image coordinates have y down; NSImage drawing has y up.
let crop = NSRect(x: cx - side / 2, y: Double(h) - cy - side / 2, width: side, height: side)
let cream = rep.colorAt(x: Int(cx), y: top + 40) ?? NSColor(srgbRed: 0.98, green: 0.94, blue: 0.89, alpha: 1)

// 2. Render the 1024 master on the macOS icon grid.
func render(size: Int) -> NSBitmapImageRep {
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    NSGraphicsContext.current?.imageInterpolation = .high
    let scale = Double(size) / 1024
    let tile = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185 * scale, yRadius: 185 * scale)

    // Soft drop shadow, as on standard macOS icons.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 18 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -8 * scale)
    shadow.set()
    cream.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    path.addClip()
    cream.setFill()
    tile.fill()
    source.draw(in: tile, from: NSRect(x: crop.minX * source.size.width / Double(w),
                                       y: crop.minY * source.size.height / Double(h),
                                       width: crop.width * source.size.width / Double(w),
                                       height: crop.height * source.size.height / Double(h)),
                operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return out
}

func write(_ rep: NSBitmapImageRep, _ url: URL) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try write(render(size: base), iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try write(render(size: base * 2), iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try write(render(size: 1024), outDir.appendingPathComponent("AppIcon-1024.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outDir.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try FileManager.default.removeItem(at: iconset)
print("Wrote \(outDir.path)/AppIcon.icns (tile crop \(Int(side)) px from source)")
