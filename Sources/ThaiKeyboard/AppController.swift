import AppKit
import ThaiKeyboardCore

/// Owns the app's top-level UI and state: follows the input source and the
/// live key events, and shows, hides and redraws the keyboard panel.
/// Held strongly for the lifetime of the app.
@MainActor
final class AppController {
    private static let inputMonitoringURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
    private static let permissionItemTitle =
        "Allow key presses: System Settings → Privacy & Security → Input Monitoring"

    private let statusMenu: StatusMenu
    private let panel: KeyboardPanel
    private var monitor: KeyEventMonitor?
    private var inputSourceObserver: InputSourceObserver?

    private var labels: LabelTable?
    private var visibility = Visibility(isThai: false)
    private var pressed = PressedKeys()

    /// Whether to show what Caps Lock types instead of hiding the panel.
    /// The single place Preferences (Task 7) plugs in; off by default.
    private var showCapsOutput: Bool { false }

    init() {
        statusMenu = StatusMenu()
        weak var weakSelf: AppController?
        panel = KeyboardPanel(onClose: { weakSelf?.userHide() })
        weakSelf = self

        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrame(Placement.defaultFrame(visible: visible, aspect: KeyboardPanel.aspect), display: false)

        statusMenu.onQuit = { NSApp.terminate(nil) }
        statusMenu.onSettings = {}  // Settings window arrives in Task 9.

        let preview = PreviewOptions(arguments: CommandLine.arguments)
        if preview.isActive {
            startPreview(preview)
            return
        }

        statusMenu.onToggleShow = { [weak self] in self?.toggleShow() }

        // Caps Lock is latched, so read where it stands now rather than
        // wait for the first flags event.
        pressed.flagsChanged(shift: false, capsLock: CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift))

        inputSourceObserver = InputSourceObserver(onChange: { [weak self] in self?.inputSourceChanged() })
        let monitor = KeyEventMonitor(onEvent: { [weak self] in self?.handle($0) })
        monitor.onStarted = { [weak self] in self?.recompute() }
        self.monitor = monitor
        inputSourceChanged()
        monitor.start()
    }

    // MARK: Live flow

    private func inputSourceChanged() {
        labels = SystemLayout.currentTranslator().map {
            LabelTable(translator: $0, keyCodes: MacBookANSI.characterKeyCodes)
        }
        panel.keyboardView.labels = labels
        visibility.inputSourceChanged(isThai: SystemLayout.current().isThai)
        pressed.reset()
        recompute()
    }

    private func handle(_ event: KeyEventMonitor.KeyEvent) {
        switch event {
        case .down(let code): pressed.keyDown(code)
        case .up(let code): pressed.keyUp(code)
        case .flags(let shift, let capsLock): pressed.flagsChanged(shift: shift, capsLock: capsLock)
        }
        recompute()
    }

    private func toggleShow() {
        if panel.isVisible {
            visibility.userHide()
        } else {
            visibility.userShow()
        }
        recompute()
    }

    private func userHide() {
        visibility.userHide()
        recompute()
    }

    private func currentMode() -> DisplayMode {
        displayMode(
            shift: pressed.shift,
            capsLock: pressed.capsLock,
            capsChangesOutput: labels?.capsChangesOutput ?? false,
            showCapsOutput: showCapsOutput
        )
    }

    /// Brings the panel, its drawing and the menu in line with the current
    /// state. Any keys held from before are cleared whenever the panel
    /// (re)appears, so nothing stays lit from a press it never saw end.
    private func recompute() {
        var mode = currentMode()
        let shouldShow = visibility.isVisible(hiddenForCaps: mode == .hiddenForCaps)
        if shouldShow, !panel.isVisible {
            pressed.reset()
            mode = currentMode()
        }

        let view = panel.keyboardView
        if view.mode != mode { view.mode = mode }
        if view.pressed != pressed.keys { view.pressed = pressed.keys }
        if view.shiftHeld != pressed.shift { view.shiftHeld = pressed.shift }

        if shouldShow, !panel.isVisible {
            panel.orderFrontRegardless()
        } else if !shouldShow, panel.isVisible {
            panel.orderOut(nil)
        }

        var actionItems: [StatusMenu.ActionItem] = []
        if let monitor, !monitor.hasPermission {
            actionItems.append(StatusMenu.ActionItem(Self.permissionItemTitle) {
                NSWorkspace.shared.open(Self.inputMonitoringURL)
            })
        }
        statusMenu.update(isShown: shouldShow, actionItems: actionItems)
    }

    // MARK: Preview

    /// `--preview-mode` / `--font` / `--snapshot`: show the Thai layout in
    /// a fixed mode, with no key events or input-source following.
    private func startPreview(_ preview: PreviewOptions) {
        panel.keyboardView.labels = SystemLayout.translator(forSourceID: "com.apple.keylayout.Thai").map {
            LabelTable(translator: $0, keyCodes: MacBookANSI.characterKeyCodes)
        }
        preview.apply(to: panel.keyboardView)
        statusMenu.update(isShown: true, actionItems: [])
        statusMenu.onToggleShow = { [weak panel] in
            guard let panel else { return }
            if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        }

        if let path = preview.snapshotPath {
            let view = panel.keyboardView
            DispatchQueue.main.async {
                let ok = Self.writeSnapshot(of: view, to: path)
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

/// Debug/preview launch arguments (used to render screenshots):
/// `--preview-mode plain|shift|caps`, `--font "<family>"`, and
/// `--snapshot <png path>` (render the keyboard offscreen, then quit).
private struct PreviewOptions {
    var mode: DisplayMode = .thai(.plain)
    var shiftHeld = false
    var fontFamily: String?
    var snapshotPath: String?
    /// `true` when any preview flag was given.
    var isActive = false

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
        isActive = ["--preview-mode", "--font", "--snapshot"].contains { arguments.contains($0) }
    }

    @MainActor func apply(to view: KeyboardView) {
        view.mode = mode
        view.shiftHeld = shiftHeld
        view.fontFamily = fontFamily
    }
}
