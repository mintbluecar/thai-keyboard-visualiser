import AppKit

/// The app's menu-bar presence: a status item titled "ก" whose menu has
/// Show/Hide keyboard, any action items (things the user needs to do),
/// Settings… and Quit.
@MainActor
final class StatusMenu: NSObject {
    /// A line in the menu telling the user something they need to do.
    /// Disabled unless it has an `action`, which runs when it's clicked.
    struct ActionItem {
        let title: String
        let action: (() -> Void)?

        init(_ title: String, action: (() -> Void)? = nil) {
            self.title = title
            self.action = action
        }
    }

    var onToggleShow: () -> Void = {}
    var onSettings: () -> Void = {}
    var onQuit: () -> Void = {}

    private let statusItem: NSStatusItem
    private var actionItems: [ActionItem] = []
    private var shownState: (isShown: Bool, titles: [String])?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.title = "ก"
        statusItem.menu = NSMenu()
        update(isShown: false, actionItems: [])
    }

    /// Rebuilds the menu for the panel's current state. Cheap to call on
    /// every key event: does nothing when nothing changed.
    func update(isShown: Bool, actionItems: [ActionItem]) {
        let titles = actionItems.map(\.title)
        if let shownState, shownState.isShown == isShown, shownState.titles == titles { return }
        shownState = (isShown, titles)
        self.actionItems = actionItems

        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()
        menu.autoenablesItems = false

        menu.addItem(item(isShown ? "Hide keyboard" : "Show keyboard", #selector(toggleShow)))
        menu.addItem(.separator())
        if !actionItems.isEmpty {
            for (index, actionItem) in actionItems.enumerated() {
                let menuItem = item(actionItem.title, #selector(performActionItem(_:)))
                menuItem.tag = index
                menuItem.isEnabled = actionItem.action != nil
                menu.addItem(menuItem)
            }
            menu.addItem(.separator())
        }
        menu.addItem(item("Settings…", #selector(settings), key: ","))
        menu.addItem(item("Quit", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    @objc private func toggleShow() {
        onToggleShow()
    }

    @objc private func performActionItem(_ sender: NSMenuItem) {
        guard actionItems.indices.contains(sender.tag) else { return }
        actionItems[sender.tag].action?()
    }

    @objc private func settings() {
        onSettings()
    }

    @objc private func quit() {
        onQuit()
    }
}
