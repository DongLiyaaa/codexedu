import AppKit

// A fixed identity mark, not a live quota gauge. Template rendering follows macOS appearance.
enum BrandIcon {
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let ring = NSBezierPath()
            ring.lineWidth = 1.65
            ring.lineCapStyle = .round
            ring.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 6.1,
                           startAngle: 55, endAngle: 5, clockwise: false)
            ring.stroke()

            let tick = NSBezierPath()
            tick.lineWidth = 1.65
            tick.lineCapStyle = .round
            tick.move(to: NSPoint(x: 9, y: 9))
            tick.line(to: NSPoint(x: 12.8, y: 11.2))
            tick.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Codex Island 额度监控"
        return image
    }
}
