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

        contentView = keyboardView
        keyboardView.addSubview(makeCloseButton(in: keyboardView.bounds))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// A small × sitting in the top-right strip of panel padding, just left
    /// of the rounded corner.
    private func makeCloseButton(in bounds: CGRect) -> NSButton {
        let side = KeyboardView.padding
        let button = NSButton(title: "×", target: self, action: #selector(closeClicked))
        button.isBordered = false
        button.font = .systemFont(ofSize: side - 1)
        button.contentTintColor = .secondaryLabelColor
        button.frame = CGRect(x: bounds.maxX - 2 * side, y: bounds.maxY - side, width: side, height: side)
        button.autoresizingMask = [.minXMargin, .minYMargin]
        return button
    }

    @objc private func closeClicked() {
        onClose()
    }
}
