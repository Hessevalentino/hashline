import AppKit

/// The assistant's toolbar icon: a square robot head with a frown, drawn as a template image so it
/// takes the toolbar's colour in light and dark mode like the SF Symbols beside it.
enum AssistantIcon {
    static let image: NSImage = {
        // 20 × 20 points, the optical size of the SF Symbols in the same toolbar.
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            NSColor.black.set()

            // Head.
            let head = NSBezierPath(roundedRect: NSRect(x: 1.75, y: 1.25, width: 16.5, height: 13.5),
                                    xRadius: 3, yRadius: 3)
            head.lineWidth = 1.5
            head.stroke()

            // Antenna.
            let antenna = NSBezierPath()
            antenna.move(to: NSPoint(x: 10, y: 14.75))
            antenna.line(to: NSPoint(x: 10, y: 16.75))
            antenna.lineWidth = 1.5
            antenna.stroke()
            NSBezierPath(ovalIn: NSRect(x: 8.5, y: 16.25, width: 3, height: 3)).fill()

            // Eyes.
            NSBezierPath(roundedRect: NSRect(x: 5.25, y: 6.75, width: 2.75, height: 2.75), xRadius: 0.5,
                         yRadius: 0.5).fill()
            NSBezierPath(roundedRect: NSRect(x: 12, y: 6.75, width: 2.75, height: 2.75), xRadius: 0.5,
                         yRadius: 0.5).fill()

            // Frowning brows, lower towards the middle.
            let brows = NSBezierPath()
            brows.move(to: NSPoint(x: 4.75, y: 11.75))
            brows.line(to: NSPoint(x: 8.5, y: 10.25))
            brows.move(to: NSPoint(x: 15.25, y: 11.75))
            brows.line(to: NSPoint(x: 11.5, y: 10.25))
            brows.lineWidth = 1.5
            brows.lineCapStyle = .round
            brows.stroke()

            // Mouth with its corners down.
            let mouth = NSBezierPath()
            mouth.move(to: NSPoint(x: 6.25, y: 3.5))
            mouth.curve(to: NSPoint(x: 13.75, y: 3.5), controlPoint1: NSPoint(x: 8, y: 5.5),
                        controlPoint2: NSPoint(x: 12, y: 5.5))
            mouth.lineWidth = 1.5
            mouth.lineCapStyle = .round
            mouth.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = String(localized: "Assistant")
        return image
    }()
}
