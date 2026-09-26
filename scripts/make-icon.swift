// Builds the macOS app icon from Design/hashline-LOGO-no-text.svg: the logo on its background colour,
// inside the macOS icon shape (824 pt rounded square on a 1024 canvas) with a soft shadow. The SVG's
// glyph fills 90 % of its canvas, so it is drawn smaller (about 70 % of the icon, Apple's guidance).
// Usage: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("Design/hashline-LOGO-no-text.svg")
/// The SVG's background (its first rect), so the margin around the smaller logo matches it.
let background = NSColor(srgbRed: 0x1c / 255, green: 0x24 / 255, blue: 0x27 / 255, alpha: 1)
/// The logo's drawn size as a share of the icon shape.
let logoScale: CGFloat = 0.78
let output = root.appendingPathComponent("Sources/Hashline/Resources/Assets.xcassets/AppIcon.appiconset")

guard let logo = NSImage(contentsOf: source) else { fatalError("Missing \(source.path)") }

func render(size: Int) -> Data {
    let scale = CGFloat(size) / 1024
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let body = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * scale, yRadius: 185 * scale)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
    shadow.shadowBlurRadius = 20 * scale
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    shape.addClip()
    background.setFill()
    shape.fill()
    context.imageInterpolation = .high
    let logoRect = body.insetBy(dx: body.width * (1 - logoScale) / 2, dy: body.height * (1 - logoScale) / 2)
    logo.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("png") }
    return png
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let pixels = points * factor
        let name = "icon_\(points)x\(points)\(factor == 2 ? "@2x" : "").png"
        try render(size: pixels).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(factor)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("Contents.json"))
let catalog = output.deletingLastPathComponent().appendingPathComponent("Contents.json")
try Data(#"{"info":{"author":"xcode","version":1}}"#.utf8).write(to: catalog)
print("Icon written to \(output.path)")
