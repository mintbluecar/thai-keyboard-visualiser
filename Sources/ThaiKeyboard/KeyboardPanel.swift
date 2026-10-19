import AppKit
import ThaiKeyboardCore

/// The floating, non-activating window that shows the keyboard. It never
/// becomes key or main, so clicking or dragging it leaves focus where it was.
final class KeyboardPanel: NSPanel {
    /// Width / height of the panel: the keyboard's proportions at scale 1.
    static var aspect: CGFloat {
        let size = KeyboardView.designSize
        return size.width / size.height
    }

    let keyboardView = KeyboardView()
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(
            contentRect: CGRect(origin: .zero, size: KeyboardView.designSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        contentAspectRatio = NSSize(width: Self.aspect, height: 1)

        acceptsMouseMovedEvents = true

        contentView = keyboardView
        keyboardView.closeButton = makeCloseButton()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// A round × in the top strip above the keys. KeyboardView sizes and
    /// places it, so it scales with the window.
    private func makeCloseButton() -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(closeClicked))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyUpOrDown
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "Hide keyboard until the input source changes"
        return button
    }

    @objc private func closeClicked() {
        onClose()
    }
}
