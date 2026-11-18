// Renders the app icon: a white Dock symbol on a blue rounded square.
// Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // macOS icon grid: the shape fills ~80% of the canvas, leaving room for the shadow.
    let rect = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let shape = NSBezierPath(roundedRect: rect, xRadius: s * 0.18, yRadius: s * 0.18)

    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.shadowBlurRadius = s * 0.02
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSShadow().set()

    NSGradient(starting: NSColor(red: 0.25, green: 0.55, blue: 1, alpha: 1),
               ending: NSColor(red: 0.1, green: 0.3, blue: 0.85, alpha: 1))!.draw(in: shape, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    let symbol = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    let sz = symbol.size
    symbol.draw(in: NSRect(x: (s - sz.width) / 2, y: (s - sz.height) / 2, width: sz.width, height: sz.height))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
