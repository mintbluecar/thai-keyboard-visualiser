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
        keyboardView.closeButton = makeCloseButton()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The system's own close button (the window traffic light). The panel
    /// never becomes key, so macOS draws it in its grey inactive style.
    /// KeyboardView places it top left.
    private func makeCloseButton() -> NSButton {
        let button = NSWindow.standardWindowButton(.closeButton, for: [.titled, .closable])
            ?? NSButton(title: "×", target: nil, action: nil)
        button.target = self
        button.action = #selector(closeClicked)
        button.toolTip = "Hide keyboard until the input source changes"
        return button
    }

    @objc private func closeClicked() {
        onClose()
    }
}
