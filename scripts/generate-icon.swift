import AppKit
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let inset = CGFloat(pixels) * 0.08
        let rect = NSRect(x: inset, y: inset, width: CGFloat(pixels) - inset * 2, height: CGFloat(pixels) - inset * 2)
        NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.17, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: CGFloat(pixels) * 0.19, yRadius: CGFloat(pixels) * 0.19).fill()
        if let symbol = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "MacPulse")?
            .withSymbolConfiguration(.init(pointSize: CGFloat(pixels) * 0.48, weight: .medium))?
            .withSymbolConfiguration(.init(paletteColors: [NSColor(calibratedRed: 0.43, green: 0.88, blue: 0.27, alpha: 1)])) {
            let box = NSRect(x: CGFloat(pixels) * 0.22, y: CGFloat(pixels) * 0.25, width: CGFloat(pixels) * 0.56, height: CGFloat(pixels) * 0.50)
            symbol.draw(in: box)
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let data = bitmap.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: URL(fileURLWithPath: "\(output)/icon_\(size)x\(size)\(suffix).png"))
    }
}
