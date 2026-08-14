import AppKit

enum StatusBarIcon {
    static let size = NSSize(width: 18, height: 18)

    static func make() -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            NSBezierPath(
                roundedRect: NSRect(x: 6.25, y: 8, width: 5.5, height: 8.5),
                xRadius: 2.75,
                yRadius: 2.75
            ).fill()

            let cradle = NSBezierPath()
            cradle.lineWidth = 1.5
            cradle.lineCapStyle = .round
            cradle.move(to: NSPoint(x: 4.5, y: 11.5))
            cradle.curve(
                to: NSPoint(x: 9, y: 5.5),
                controlPoint1: NSPoint(x: 4.5, y: 7.7),
                controlPoint2: NSPoint(x: 6.4, y: 5.5)
            )
            cradle.curve(
                to: NSPoint(x: 13.5, y: 11.5),
                controlPoint1: NSPoint(x: 11.6, y: 5.5),
                controlPoint2: NSPoint(x: 13.5, y: 7.7)
            )
            cradle.stroke()

            let stand = NSBezierPath()
            stand.lineWidth = 1.5
            stand.lineCapStyle = .round
            stand.move(to: NSPoint(x: 9, y: 5.5))
            stand.line(to: NSPoint(x: 9, y: 3.5))
            stand.move(to: NSPoint(x: 6.5, y: 3.5))
            stand.line(to: NSPoint(x: 11.5, y: 3.5))
            stand.stroke()

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MicPilot"
        return image
    }
}
