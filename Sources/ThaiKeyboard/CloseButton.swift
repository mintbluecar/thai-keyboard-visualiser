import AppKit

/// A red close button drawn like a macOS window's traffic light. The real
/// one (`NSWindow.standardWindowButton`) is drawn grey in a window that
/// isn't key, and the keyboard panel never becomes key, so it would always
/// look inactive. The × shows on hover, as on a real window.
final class CloseButton: NSButton {
    static let diameter: CGFloat = 14

    private static let fill = NSColor(srgbRed: 0xff / 255, green: 0x5f / 255, blue: 0x57 / 255, alpha: 1)
    private static let rim = NSColor(srgbRed: 0xe0 / 255, green: 0x44 / 255, blue: 0x3e / 255, alpha: 1)
    private static let cross = NSColor(srgbRed: 0x4d / 255, green: 0x00 / 255, blue: 0x00 / 255, alpha: 1)

    private var hovering = false { didSet { needsDisplay = true } }

    init(target: AnyObject, action: Selector) {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter))
        self.target = target
        self.action = action
        isBordered = false
        title = ""
        setAccessibilityLabel("Hide keyboard")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // .activeAlways: the app is almost never active.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        let circle = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(ovalIn: circle)
        (isHighlighted ? Self.rim : Self.fill).setFill()
        path.fill()
        Self.rim.setStroke()
        path.lineWidth = 0.5
        path.stroke()

        guard hovering || isHighlighted else { return }
        let arm = bounds.width * 0.2
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        let cross = NSBezierPath()
        cross.move(to: CGPoint(x: centre.x - arm, y: centre.y - arm))
        cross.line(to: CGPoint(x: centre.x + arm, y: centre.y + arm))
        cross.move(to: CGPoint(x: centre.x - arm, y: centre.y + arm))
        cross.line(to: CGPoint(x: centre.x + arm, y: centre.y - arm))
        cross.lineWidth = 1.2
        cross.lineCapStyle = .round
        Self.cross.setStroke()
        cross.stroke()
    }
}
