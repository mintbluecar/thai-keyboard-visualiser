import AppKit
import ThaiKeyboardCore

/// Owns the app's top-level UI. Held strongly for the lifetime of the app.
@MainActor
final class AppController {
    private let statusMenu: StatusMenu
    private let panel: KeyboardPanel

    init() {
        statusMenu = StatusMenu(onQuit: {
            NSApp.terminate(nil)
        })

        // Temporary wiring until visibility (Task 6): show the panel at
        // launch with the Thai layout's labels.
        // Temporary: × just hides the panel; visibility rules come in Task 6.
        weak var closingPanel: KeyboardPanel?
        let panel = KeyboardPanel(onClose: { closingPanel?.orderOut(nil) })
        closingPanel = panel
        self.panel = panel
        panel.keyboardView.labels = SystemLayout.translator(forSourceID: "com.apple.keylayout.Thai").map {
            LabelTable(translator: $0, keyCodes: MacBookANSI.characterKeyCodes)
        }

        let preview = PreviewOptions(arguments: CommandLine.arguments)
        preview.apply(to: panel.keyboardView)

        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrame(Placement.defaultFrame(visible: visible, aspect: KeyboardPanel.aspect), display: false)

        if let path = preview.snapshotPath {
            DispatchQueue.main.async {
                let ok = Self.writeSnapshot(of: panel.keyboardView, to: path)
                if ok { NSApp.terminate(nil) } else { exit(1) }
            }
            return
        }

        panel.orderFrontRegardless()
    }

    /// Renders `view` offscreen at its current size into a PNG at `path`.
    private static func writeSnapshot(of view: NSView, to path: String) -> Bool {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}

/// Debug/preview launch arguments, temporary until Preferences (Task 7):
/// `--preview-mode plain|shift|caps`, `--font "<family>"`, and
/// `--snapshot <png path>` (render the keyboard offscreen, then quit).
private struct PreviewOptions {
    var mode: DisplayMode = .thai(.plain)
    var shiftHeld = false
    var fontFamily: String?
    var snapshotPath: String?

    init(arguments: [String]) {
        func value(after flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        switch value(after: "--preview-mode") {
        case "shift": mode = .thai(.shift); shiftHeld = true
        case "caps": mode = .capsOutput(.caps)
        default: break
        }
        fontFamily = value(after: "--font")
        snapshotPath = value(after: "--snapshot")
    }

    @MainActor func apply(to view: KeyboardView) {
        view.mode = mode
        view.shiftHeld = shiftHeld
        view.fontFamily = fontFamily
    }
}
