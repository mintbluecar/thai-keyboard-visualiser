import AppKit

/// The keyboard's close button: a round badge in the keys' own colours with
/// a light-grey ×, drawn at whatever size KeyboardView gives it.
final class CloseBadge: NSButton {
    // Same colours as the keys and their labels (KeyboardView).
    private static let fill = NSColor(srgbRed: 0x3a / 255, green: 0x3a / 255, blue: 0x40 / 255, alpha: 1)
    private static let pressedFill = NSColor(srgbRed: 0x55 / 255, green: 0x55 / 255, blue: 0x5c / 255, alpha: 1)
    private static let rim = NSColor(srgbRed: 0x1e / 255, green: 0x1e / 255, blue: 0x22 / 255, alpha: 1)
    private static let cross = NSColor(srgbRed: 0xcc / 255, green: 0xcc / 255, blue: 0xcc / 255, alpha: 1)

    init(target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        title = ""
        setAccessibilityLabel("Hide keyboard")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        let rimWidth = max(1, bounds.width * 0.08)
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: rimWidth / 2, dy: rimWidth / 2))
        (isHighlighted ? Self.pressedFill : Self.fill).setFill()
        circle.fill()
        Self.rim.setStroke()
        circle.lineWidth = rimWidth
        circle.stroke()

        let arm = bounds.width * 0.18
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        let cross = NSBezierPath()
        cross.move(to: CGPoint(x: centre.x - arm, y: centre.y - arm))
        cross.line(to: CGPoint(x: centre.x + arm, y: centre.y + arm))
        cross.move(to: CGPoint(x: centre.x - arm, y: centre.y + arm))
        cross.line(to: CGPoint(x: centre.x + arm, y: centre.y - arm))
        cross.lineWidth = max(1.2, bounds.width * 0.09)
        cross.lineCapStyle = .round
        Self.cross.setStroke()
        cross.stroke()
    }
}
