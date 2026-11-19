import AppKit
let out = CommandLine.arguments[1]
for s in [16, 32, 64, 128, 256, 512, 1024] {
    let img = NSImage(size: NSSize(width: s, height: s))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: s, pixelsHigh: s, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let S = CGFloat(s), inset = S * 0.09
    let r = NSRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
    NSColor(red: 0.76, green: 0.34, blue: 0.2, alpha: 1).setFill()
    NSBezierPath(roundedRect: r, xRadius: S * 0.2, yRadius: S * 0.2).fill()
    let cfg = NSImage.SymbolConfiguration(pointSize: S * 0.42, weight: .semibold).applying(.init(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let z = sym.size
        sym.draw(in: NSRect(x: (S - z.width) / 2, y: (S - z.height) / 2, width: z.width, height: z.height))
    }
    NSGraphicsContext.current = nil
    _ = img
    let png = rep.representation(using: .png, properties: [:])!
    let names = s == 1024 ? ["icon_512x512@2x"] : s == 16 ? ["icon_16x16"] : ["icon_\(s)x\(s)", "icon_\(s/2)x\(s/2)@2x"]
    for n in names where n != "icon_64x64" { try! png.write(to: URL(fileURLWithPath: "\(out)/\(n).png")) }
}
