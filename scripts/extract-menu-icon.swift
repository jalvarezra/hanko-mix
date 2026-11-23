// Builds the menu bar template icon from the concept 01 glyph in hanko-concepts.png.
// Usage: swift scripts/extract-menu-icon.swift App/Branding/HankoMenuBar-concept01.png App [preview.png]
// (HankoMenuBar-concept01.png is the concept 01 glyph cropped from hanko-concepts.png.)
// Alpha comes from each pixel's darkness, the glyph is trimmed to its bounds and
// scaled to 18 pt tall at 1×, 2× and 3× as MenuBarIcon(.png|@2x|@3x).
import AppKit

let args = CommandLine.arguments
guard args.count >= 3, let src = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: args[1]))) else {
    print("usage: extract-menu-icon.swift <concept-crop.png> <out-dir> [preview.png]"); exit(64)
}
let w = src.pixelsWide, h = src.pixelsHigh
// Background is the board's cream; ink is near-black. Map darkness to alpha.
func alpha(_ x: Int, _ y: Int) -> CGFloat {
    guard let c = src.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return 0 }
    let luminance = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
    return min(1, max(0, (0.88 - luminance) / 0.7))
}
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h { for x in 0..<w where alpha(x, y) > 0.5 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
let gw = maxX - minX + 1, gh = maxY - minY + 1

// Full-resolution template (black + alpha).
let glyph = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: gw, pixelsHigh: gh, bitsPerSample: 8, samplesPerPixel: 4,
                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
for y in 0..<gh { for x in 0..<gw {
    glyph.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: alpha(x + minX, y + minY)), atX: x, y: y)
} }
let glyphImage = NSImage(size: NSSize(width: gw, height: gh))
glyphImage.addRepresentation(glyph)

let pointHeight: CGFloat = 18
let pointWidth = (CGFloat(gw) / CGFloat(gh) * pointHeight).rounded()
func render(scale: Int, color: NSColor? = nil, background: NSColor? = nil, canvas: NSSize? = nil, at origin: NSPoint = .zero) -> NSBitmapImageRep {
    let size = canvas ?? NSSize(width: pointWidth * CGFloat(scale), height: pointHeight * CGFloat(scale))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    if let background { background.setFill(); NSRect(origin: .zero, size: size).fill() }
    let rect = NSRect(x: origin.x, y: origin.y, width: pointWidth * CGFloat(scale), height: pointHeight * CGFloat(scale))
    glyphImage.draw(in: rect)
    if let color { color.set(); rect.fill(using: .sourceAtop) }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}
let out = URL(fileURLWithPath: args[2])
for (suffix, scale) in [("", 1), ("@2x", 2), ("@3x", 3)] {
    try render(scale: scale).representation(using: .png, properties: [:])!
        .write(to: out.appendingPathComponent("MenuBarIcon\(suffix).png"))
}
print("glyph \(gw)x\(gh) px → \(Int(pointWidth))x\(Int(pointHeight)) pt")

if args.count == 4 {
    // Real-size preview at 2×: light and dark menu bars.
    let canvas = NSSize(width: 200, height: 112)
    let preview = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 112, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: preview)
    for (i, (bg, fg)) in [(NSColor(white: 0.93, alpha: 1), NSColor.black), (NSColor(white: 0.17, alpha: 1), NSColor.white)].enumerated() {
        let y = CGFloat(56 - i * 56)
        bg.setFill(); NSRect(x: 0, y: y, width: canvas.width, height: 56).fill()
        let icon = render(scale: 2, color: fg)
        icon.draw(in: NSRect(x: 80, y: y + 10, width: pointWidth * 2, height: pointHeight * 2))
    }
    NSGraphicsContext.restoreGraphicsState()
    try preview.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
}
