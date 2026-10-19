import AppKit

/// The app's menu-bar presence: a status item titled "ก" with a Quit item.
@MainActor
final class StatusMenu {
    private let statusItem: NSStatusItem
    private let onQuit: () -> Void

    init(onQuit: @escaping () -> Void) {
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "ก"

        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit", action: #selector(StatusMenu.quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func quit() {
        onQuit()
    }
}
