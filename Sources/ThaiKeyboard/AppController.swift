import AppKit
import ThaiKeyboardCore

/// Owns the app's top-level UI and state: follows the input source and the
/// live key events, and shows, hides and redraws the keyboard panel.
/// Held strongly for the lifetime of the app.
@MainActor
final class AppController {
    private static let inputMonitoringURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
    private static let firstLaunchKey = "ThaiKeyboard.didCompleteFirstLaunch"

    private let statusMenu: StatusMenu
    private let panel: KeyboardPanel
    private var monitor: KeyEventMonitor?
    private var inputSourceObserver: InputSourceObserver?
    private var hotkeyCenter: HotkeyCenter?

    private var labels: LabelTable?
    private var visibility = Visibility(isThai: false)
    private var pressed = PressedKeys()
    /// The hotkeys `HotkeyCenter.register` couldn't register, surfaced in
    /// the compatibility report.
    private var failedHotkeys: Set<HotkeyAction> = []

    private let prefs = Preferences()
    /// Set while `restoreFrame()` is moving/resizing the panel
    /// programmatically, so that doesn't get saved back as a user move.
    private var isRestoringFrame = false
    /// Set if `LoginItem.apply` throws on first launch. Settings (Task 9)
    /// will surface this to the user; nothing about it is logged here.
    private var firstLaunchLoginItemError: Error?

    /// Whether to show what Caps Lock types instead of hiding the panel.
    private var showCapsOutput: Bool { prefs.showCapsOutput }

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

        panel.alphaValue = CGFloat(prefs.opacity)
        panel.keyboardView.fontFamily = prefs.fontFamily
        restoreFrame()
        observeFrameChanges()
        applyFirstLaunchLoginItemIfNeeded()

        statusMenu.onToggleShow = { [weak self] in self?.toggleShow() }

        // Caps Lock is latched, so read where it stands now rather than
        // wait for the first flags event.
        pressed.flagsChanged(shift: false, capsLock: CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift))

        inputSourceObserver = InputSourceObserver(onChange: { [weak self] in self?.inputSourceChanged() })
        let monitor = KeyEventMonitor(onEvent: { [weak self] in self?.handle($0) })
        monitor.onRunningChanged = { [weak self] in self?.keyMonitorRunningChanged() }
        self.monitor = monitor

        let hotkeyCenter = HotkeyCenter(onAction: { [weak self] in self?.performHotkeyAction($0) })
        self.hotkeyCenter = hotkeyCenter
        failedHotkeys = hotkeyCenter.register(prefs.hotkeys)

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

    /// The tap started or died. Either way, any key held before can't be
    /// trusted (a dead tap never delivers its key-up), so clear them.
    private func keyMonitorRunningChanged() {
        pressed.reset()
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

        let report = compatibilityReport()
        let actionItems = report.actionItems.map { title in
            title == CompatibilityReport.keyPressesNotAllowedLine
                ? StatusMenu.ActionItem(title) { NSWorkspace.shared.open(Self.inputMonitoringURL) }
                : StatusMenu.ActionItem(title)
        }
        statusMenu.update(isShown: shouldShow, actionItems: actionItems)
    }

    /// The current compatibility snapshot: input source, physical keyboard,
    /// Input Monitoring permission, Caps Lock behaviour, and any hotkeys
    /// that failed to register.
    private func compatibilityReport() -> CompatibilityReport {
        CompatibilityReport(
            inputSource: SystemLayout.current(),
            keyboardType: SystemLayout.keyboardType(),
            inputMonitoring: monitor?.hasPermission ?? false,
            capsChangesOutput: labels?.capsChangesOutput ?? false,
            failedHotkeys: failedHotkeys
        )
    }

    /// Runs a global hotkey's action: snaps or resizes the panel on the
    /// screen it's currently on (even while hidden), then saves the new
    /// frame as the user's preference.
    private func performHotkeyAction(_ action: HotkeyAction) {
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let newFrame: CGRect
        switch action {
        case .snapTop: newFrame = Placement.snapped(panel.frame, to: .top, in: visible)
        case .snapBottom: newFrame = Placement.snapped(panel.frame, to: .bottom, in: visible)
        case .snapLeft: newFrame = Placement.snapped(panel.frame, to: .left, in: visible)
        case .snapRight: newFrame = Placement.snapped(panel.frame, to: .right, in: visible)
        case .snapTopLeft: newFrame = Placement.snapped(panel.frame, to: .topLeft, in: visible)
        case .snapTopRight: newFrame = Placement.snapped(panel.frame, to: .topRight, in: visible)
        case .snapBottomLeft: newFrame = Placement.snapped(panel.frame, to: .bottomLeft, in: visible)
        case .snapBottomRight: newFrame = Placement.snapped(panel.frame, to: .bottomRight, in: visible)
        case .bigger: newFrame = Placement.resized(panel.frame, step: 1, aspect: KeyboardPanel.aspect, in: visible)
        case .smaller: newFrame = Placement.resized(panel.frame, step: -1, aspect: KeyboardPanel.aspect, in: visible)
        }
        panel.setFrame(newFrame, display: true)
        prefs.frame = newFrame
    }

    // MARK: Preferences

    /// Observes the panel's own move/resize so a user drag or hotkey
    /// resize (Task 8) is saved, and the screen configuration changing so
    /// the panel is re-clamped into whichever screen it's now on.
    private func observeFrameChanges() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveFrameIfNeeded() }
        }
        center.addObserver(forName: NSWindow.didResizeNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveFrameIfNeeded() }
        }
        center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restoreFrame() }
        }
    }

    private func saveFrameIfNeeded() {
        guard !isRestoringFrame else { return }
        prefs.frame = panel.frame
    }

    /// Restores the saved frame (clamped into its screen's visible area),
    /// or falls back to `Placement.defaultFrame` when nothing was saved.
    /// Used at launch and on `didChangeScreenParametersNotification`.
    private func restoreFrame() {
        let saved = prefs.frame
        let visible = visibleFrame(containing: saved)
        let newFrame = saved.map { Placement.clamped($0, in: visible) }
            ?? Placement.defaultFrame(visible: visible, aspect: KeyboardPanel.aspect)

        isRestoringFrame = true
        panel.setFrame(newFrame, display: false)
        isRestoringFrame = false
    }

    /// The visible frame of the screen containing `frame`'s centre, or the
    /// main screen (or a sensible default) when there's no saved frame or
    /// no screen contains it.
    private func visibleFrame(containing frame: CGRect?) -> CGRect {
        let fallback = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        guard let frame else { return fallback }
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(centre) }?.visibleFrame ?? fallback
    }

    /// On first launch only (a namespaced UserDefaults flag not yet set),
    /// applies `prefs.startAtLogin` as the login item state. An error is
    /// kept (not thrown further, not logged) for Settings (Task 9) to show.
    private func applyFirstLaunchLoginItemIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.firstLaunchKey) else { return }
        do {
            try LoginItem.apply(prefs.startAtLogin)
        } catch {
            firstLaunchLoginItemError = error
        }
        defaults.set(true, forKey: Self.firstLaunchKey)
    }

    // MARK: Preview

    /// `--preview-mode` / `--font` / `--snapshot`: show the Thai layout in
    /// a fixed mode, with no key events or input-source following.
    private func startPreview(_ preview: PreviewOptions) {
        panel.keyboardView.labels = SystemLayout.translator(forSourceID: "com.apple.keylayout.Thai").map {
            LabelTable(translator: $0, keyCodes: MacBookANSI.characterKeyCodes)
        }
        preview.apply(to: panel.keyboardView, fontFamilyOverride: prefs.fontFamily)
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

    /// `fontFamily` (`--font`) wins when given; otherwise falls back to
    /// `fontFamilyOverride` (the user's saved preference). Either way,
    /// nothing here is persisted.
    @MainActor func apply(to view: KeyboardView, fontFamilyOverride: String?) {
        view.mode = mode
        view.shiftHeld = shiftHeld
        view.fontFamily = fontFamily ?? fontFamilyOverride
    }
}
