import AppKit
import Carbon.HIToolbox
import ThaiKeyboardCore

/// Draws the MacBook keyboard: panel background, keys, Thai labels, blue
/// US corner letters and grey modifier labels.
///
/// All drawing happens in "design points" (the proportions from the Global
/// Constraints at a 58 pt key) under a uniform scale of
/// `bounds.width / designSize.width`, so everything scales with the window.
final class KeyboardView: NSView {
    var labels: LabelTable? { didSet { needsDisplay = true } }
    var mode: DisplayMode = .thai(.plain) { didSet { needsDisplay = true } }
    var pressed: Set<UInt16> = [] { didSet { needsDisplay = true } }
    var shiftHeld = false { didSet { needsDisplay = true } }
    var fontFamily: String? { didSet { needsDisplay = true } }

    // Proportions at scale 1 (Global Constraints).
    static let keySize: CGFloat = 58
    static let keyGap: CGFloat = 6
    static let padding: CGFloat = 12
    private static let keyRadius: CGFloat = 8
    private static let panelRadius: CGFloat = 14
    private static let thaiSize: CGFloat = 28
    private static let thaiNudge: CGFloat = 8
    private static let cornerSize: CGFloat = 14
    private static let cornerInset = CGPoint(x: 6, y: 4)
    private static let modifierSize: CGFloat = 12

    /// The × floats diagonally off the keyboard's top-right corner, in a
    /// transparent margin above and right of the keyboard. Clicks on the
    /// transparent margin pass through to whatever is underneath.
    private static let overhang: CGFloat = 18
    private static let closeSize: CGFloat = 16
    /// How long the × stays after the pointer leaves the keyboard, so there's
    /// time to reach it across the transparent margin.
    private static let closeHideDelay: TimeInterval = 0.6

    /// The keyboard itself at scale 1: keys plus gaps plus padding.
    static var keyboardSize: CGSize {
        let units = MacBookANSI.unitSize
        return CGSize(
            width: units.width * keySize + (units.width - 1) * keyGap + 2 * padding,
            height: units.height * keySize + (units.height - 1) * keyGap + 2 * padding
        )
    }

    /// The whole window at scale 1: the keyboard plus the overhang.
    static var designSize: CGSize {
        CGSize(width: keyboardSize.width + overhang, height: keyboardSize.height + overhang)
    }

    /// The × button. The view sizes and places it, so it scales with the
    /// window, and shows it only while the pointer is over the keyboard.
    var closeButton: NSButton? {
        didSet {
            oldValue?.removeFromSuperview()
            if let closeButton {
                closeButton.alphaValue = 0
                addSubview(closeButton)
            }
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        guard let closeButton else { return }
        let scale = bounds.width / Self.designSize.width
        let side = Self.closeSize * scale
        let board = Self.keyboardSize
        let centre = CGPoint(x: (board.width + Self.overhang / 2) * scale,
                             y: (board.height + Self.overhang / 2) * scale)
        closeButton.frame = CGRect(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Hide keyboard")?
            .withSymbolConfiguration(.init(pointSize: side * 0.65, weight: .semibold))
        // A shadow so the light × reads over dark and light backgrounds.
        closeButton.wantsLayer = true
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = .zero
        closeButton.shadow = shadow
    }

    // MARK: Show the × on hover
    //
    // .activeAlways: the app is almost never active, and tracking areas are
    // otherwise only live in the key window or active app (NSTrackingArea.h).

    private var hideCloseWork: DispatchWorkItem?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { setCloseVisible(true) }
    override func mouseExited(with event: NSEvent) { setCloseVisible(false) }

    /// Shows the × at once; hides it after a short delay, cancelled if the
    /// pointer comes back (to the keyboard or to the × itself).
    private func setCloseVisible(_ visible: Bool) {
        hideCloseWork?.cancel()
        hideCloseWork = nil
        guard let closeButton else { return }
        if visible {
            closeButton.animator().alphaValue = 1
        } else {
            let work = DispatchWorkItem { closeButton.animator().alphaValue = 0 }
            hideCloseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeHideDelay, execute: work)
        }
    }

    // Colours (Global Constraints and the approved mockup).
    private enum Colour {
        static let panel = CGColor(srgbRed: 0x1e / 255, green: 0x1e / 255, blue: 0x22 / 255, alpha: 1)
        static let key = CGColor(srgbRed: 0x3a / 255, green: 0x3a / 255, blue: 0x40 / 255, alpha: 1)
        static let held = CGColor(srgbRed: 0xe8 / 255, green: 0xa2 / 255, blue: 0x3a / 255, alpha: 1)
        static let shiftOn = CGColor(srgbRed: 0x5a / 255, green: 0x6c / 255, blue: 0xff / 255, alpha: 1)
        static let text = CGColor(srgbRed: 0xf2 / 255, green: 0xf2 / 255, blue: 0xf2 / 255, alpha: 1)
        static let heldText = CGColor(srgbRed: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1)
        static let corner = CGColor(srgbRed: 0x7c / 255, green: 0xc4 / 255, blue: 0xff / 255, alpha: 1)
        static let heldCorner = CGColor(srgbRed: 0x2a / 255, green: 0x2a / 255, blue: 0x2a / 255, alpha: 1)
        static let modifier = CGColor(srgbRed: 0xaa / 255, green: 0xaa / 255, blue: 0xaa / 255, alpha: 1)
        static let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = bounds.width / Self.designSize.width
        // The keyboard sits bottom left; any overhang stays transparent.
        let design = Self.keyboardSize

        context.saveGState()
        context.scaleBy(x: scale, y: scale)

        context.setFillColor(Colour.panel)
        context.addPath(CGPath(
            roundedRect: CGRect(origin: .zero, size: design),
            cornerWidth: Self.panelRadius, cornerHeight: Self.panelRadius, transform: nil
        ))
        context.fillPath()

        let resolver = FontResolver(preferredFamily: fontFamily)
        let cornerFont = CTFontCreateUIFontForLanguage(.emphasizedSystem, Self.cornerSize, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, Self.cornerSize, nil)
        let modifierFont = CTFontCreateUIFontForLanguage(.system, Self.modifierSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, Self.modifierSize, nil)

        for key in MacBookANSI.keys {
            drawKey(key, design: design, resolver: resolver, cornerFont: cornerFont,
                    modifierFont: modifierFont, context: context)
        }
        context.restoreGState()
    }

    private func drawKey(_ key: KeySpec, design: CGSize, resolver: FontResolver, cornerFont: CTFont,
                         modifierFont: CTFont, context: CGContext) {
        let rect = Self.keyRect(key.rect, designHeight: design.height)
        let isHeld = pressed.contains(key.keyCode)
        let isShiftOn = shiftHeld && (key.keyCode == UInt16(kVK_Shift) || key.keyCode == UInt16(kVK_RightShift))

        context.setFillColor(isHeld ? Colour.held : isShiftOn ? Colour.shiftOn : Colour.key)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: Self.keyRadius, cornerHeight: Self.keyRadius, transform: nil))
        context.fillPath()

        switch key.kind {
        case .modifier(let label):
            context.setFillColor(isHeld ? Colour.heldText : isShiftOn ? Colour.white : Colour.modifier)
            GlyphDrawing.drawCentred(label, font: modifierFont, in: rect, context: context)

        case .character:
            let centre = centreLabel(for: key.keyCode)
            if !centre.isEmpty {
                // Centre in the key below a top strip of `thaiNudge`, as the
                // mockup's `padding-top: 8px` does.
                var textRect = rect
                textRect.size.height -= Self.thaiNudge
                context.setFillColor(isHeld ? Colour.heldText : Colour.text)
                GlyphDrawing.drawCentred(centre, font: resolver.font(for: centre, size: Self.thaiSize),
                                         in: textRect, context: context)
            }

            let corner = Self.usCorner[key.keyCode] ?? ""
            let hideCorner: Bool
            if case .capsOutput = mode {
                hideCorner = corner.caseInsensitiveCompare(centre) == .orderedSame
            } else {
                hideCorner = false
            }
            if !hideCorner {
                context.setFillColor(isHeld ? Colour.heldCorner : Colour.corner)
                GlyphDrawing.drawLine(corner, font: cornerFont,
                                      topLeft: CGPoint(x: rect.minX + Self.cornerInset.x, y: rect.maxY - Self.cornerInset.y),
                                      context: context)
            }
        }
    }

    private func centreLabel(for keyCode: UInt16) -> String {
        guard let labels else { return "" }
        switch mode {
        case .thai(let state), .capsOutput(let state):
            return labels.label(keyCode, state)
        case .hiddenForCaps:
            return ""
        }
    }

    /// `unitRect` (key units, y down) as a y-up rect in design points. A key
    /// spanning `w` units is `w` keys plus the `w - 1` gaps it covers wide,
    /// so half-height keys stacked with one gap fill exactly one key height.
    private static func keyRect(_ unitRect: CGRect, designHeight: CGFloat) -> CGRect {
        let pitch = keySize + keyGap
        let width = unitRect.width * pitch - keyGap
        let height = unitRect.height * pitch - keyGap
        let top = padding + unitRect.minY * pitch
        return CGRect(x: padding + unitRect.minX * pitch, y: designHeight - top - height, width: width, height: height)
    }

    /// The US key each character key is, as printed on the physical key:
    /// uppercase letters, plain symbols. Names the key, not a layout label.
    private static let usCorner: [UInt16: String] = {
        let pairs: [(Int, String)] = [
            (kVK_ANSI_Grave, "`"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"), (kVK_ANSI_4, "4"),
            (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
            (kVK_ANSI_0, "0"), (kVK_ANSI_Minus, "-"), (kVK_ANSI_Equal, "="),
            (kVK_ANSI_Q, "Q"), (kVK_ANSI_W, "W"), (kVK_ANSI_E, "E"), (kVK_ANSI_R, "R"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_Y, "Y"), (kVK_ANSI_U, "U"), (kVK_ANSI_I, "I"), (kVK_ANSI_O, "O"), (kVK_ANSI_P, "P"),
            (kVK_ANSI_LeftBracket, "["), (kVK_ANSI_RightBracket, "]"), (kVK_ANSI_Backslash, "\\"),
            (kVK_ANSI_A, "A"), (kVK_ANSI_S, "S"), (kVK_ANSI_D, "D"), (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"),
            (kVK_ANSI_H, "H"), (kVK_ANSI_J, "J"), (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"),
            (kVK_ANSI_Semicolon, ";"), (kVK_ANSI_Quote, "'"),
            (kVK_ANSI_Z, "Z"), (kVK_ANSI_X, "X"), (kVK_ANSI_C, "C"), (kVK_ANSI_V, "V"), (kVK_ANSI_B, "B"),
            (kVK_ANSI_N, "N"), (kVK_ANSI_M, "M"), (kVK_ANSI_Comma, ","), (kVK_ANSI_Period, "."), (kVK_ANSI_Slash, "/"),
        ]
        return Dictionary(uniqueKeysWithValues: pairs.map { (UInt16($0.0), $0.1) })
    }()
}
