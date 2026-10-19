import AppKit
import SwiftUI
import ThaiKeyboardCore

/// Owns the app's top-level UI and state: follows the input source and the
/// live key events, and shows, hides and redraws the keyboard panel.
/// Held strongly for the lifetime of the app.
@MainActor
final class AppController {
    private static let inputMonitoringURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
    private static let firstLaunchKey = "ThaiKeyboard.didCompleteFirstLaunch"
    /// How often held keys, Shift and Caps Lock are checked against the
    /// system's own key state while any of them is on.
    private static let reconcileInterval: TimeInterval = 0.25

    private let statusMenu: StatusMenu
    private let panel: KeyboardPanel
    private var monitor: KeyEventMonitor?
    private var inputSourceObserver: InputSourceObserver?
    private var hotkeyCenter: HotkeyCenter?

    private var labels: LabelTable?
    private var visibility = Visibility(isThai: false)
    private var pressed = PressedKeys()
    /// Runs only while `pressed.needsReconcile`; see `updateReconcileTimer`.
    private var reconcileTimer: Timer?
    /// The hotkeys `HotkeyCenter.register` couldn't register, surfaced in
    /// the compatibility report. Settings reads this to mark those rows.
    private(set) var failedHotkeys: Set<HotkeyAction> = []

    let prefs = Preferences()
    /// Set while `restoreFrame()` is moving/resizing the panel
    /// programmatically, so that doesn't get saved back as a user move.
    private var isRestoringFrame = false
    /// Set if `LoginItem.apply` throws on first launch. Settings surfaces
    /// this to the user; nothing about it is logged here.
    private(set) var firstLaunchLoginItemError: Error?

    /// Called whenever `compatibilityReport()` might have changed: the
    /// input source changed, the key monitor's tap started/stopped (so
    /// Input Monitoring permission may have too), or hotkeys were
    /// (re)registered. Deliberately *not* called from every `recompute()`
    /// — that runs on every key event, and nothing in the report depends
    /// on which keys are held. `SettingsModel` subscribes while its
    /// window exists, to keep its compatibility section live.
    var onCompatibilityChanged: (() -> Void)?

    private var settingsWindow: NSWindow?
    private var settingsModel: SettingsModel?

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
        statusMenu.onSettings = { [weak self] in self?.showSettings() }

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
        syncFlagsFromSystem()

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
        onCompatibilityChanged?()
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
    /// trusted (a dead tap never delivers its key-up), so clear them, and
    /// take Shift and Caps Lock from the system as they stand now.
    private func keyMonitorRunningChanged() {
        pressed.reset()
        syncFlagsFromSystem()
        recompute()
        onCompatibilityChanged?()
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

    /// Sets Shift and Caps Lock from the system's current modifier state.
    private func syncFlagsFromSystem() {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        pressed.flagsChanged(shift: flags.contains(.maskShift), capsLock: flags.contains(.maskAlphaShift))
    }

    /// Event taps get no keyboard events while Secure Event Input is on
    /// (Apple TN2150), so a key-up or flags change in a password field
    /// can be missed, leaving a key lit or the panel hidden for Caps Lock.
    /// While anything is held or latched, `reconcileTimer` checks the
    /// system's key state: keys it no longer reports down are dropped and
    /// Shift/Caps Lock are re-read.
    private func reconcileWithSystem() {
        let before = pressed
        pressed.reconcile { CGEventSource.keyState(.combinedSessionState, key: $0) }
        syncFlagsFromSystem()
        if pressed != before { recompute() }
    }

    private func updateReconcileTimer() {
        if pressed.needsReconcile, reconcileTimer == nil {
            reconcileTimer = Timer.scheduledTimer(withTimeInterval: Self.reconcileInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.reconcileWithSystem() }
            }
        } else if !pressed.needsReconcile, let timer = reconcileTimer {
            timer.invalidate()
            reconcileTimer = nil
        }
    }

    /// Brings the panel, its drawing and the menu in line with the current
    /// state. Whenever the panel (re)appears, held keys are cleared and
    /// Shift/Caps Lock re-read from the system, so nothing stays lit from a
    /// press it never saw end.
    private func recompute() {
        var mode = currentMode()
        var shouldShow = visibility.isVisible(hiddenForCaps: mode == .hiddenForCaps)
        if shouldShow, !panel.isVisible {
            pressed.reset()
            syncFlagsFromSystem()
            mode = currentMode()
            shouldShow = visibility.isVisible(hiddenForCaps: mode == .hiddenForCaps)
        }
        updateReconcileTimer()

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
    func compatibilityReport() -> CompatibilityReport {
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

    // MARK: Settings

    /// Shows the Settings window, creating it (and its `SettingsModel`)
    /// the first time. It's the one window besides the panel, and the one
    /// allowed to become key, so this activates the app.
    func showSettings() {
        if settingsWindow == nil {
            let model = SettingsModel(controller: self)
            let hosting = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "ThaiKeyboard Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsModel = model
            settingsWindow = window
        }
        settingsModel?.refresh()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Applies `family` (`nil` = system Thai) to the keyboard immediately
    /// and persists it (Settings' font picker).
    func applyFontFamily(_ family: String?) {
        prefs.fontFamily = family
        panel.keyboardView.fontFamily = family
    }

    /// Applies `opacity` (clamped to `0.2...1.0` by `Preferences`) to the
    /// panel immediately and persists it (Settings' opacity slider).
    func applyOpacity(_ opacity: Double) {
        prefs.opacity = opacity
        panel.alphaValue = CGFloat(prefs.opacity)
    }

    /// Persists `show` and recomputes the panel's display mode
    /// immediately (Settings' Caps Lock toggle).
    func applyShowCapsOutput(_ show: Bool) {
        prefs.showCapsOutput = show
        recompute()
    }

    /// Resizes the panel to `percent` (clamped to `0.25...1.0`) of its
    /// current screen's visible width, about its current centre, via the
    /// same `Placement.resized` path a hotkey resize uses, then saves the
    /// frame.
    func applySizePercent(_ percent: Double) {
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let width = visible.width * min(max(percent, 0.25), 1.0)
        let newFrame = Placement.resized(panel.frame, toWidth: width, aspect: KeyboardPanel.aspect, in: visible)
        panel.setFrame(newFrame, display: true)
        prefs.frame = newFrame
    }

    /// The panel's current width as a fraction of its screen's visible
    /// width — the size slider's initial value.
    func currentSizePercent() -> Double {
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        guard visible.width > 0 else { return 0.6 }
        return Double(panel.frame.width / visible.width)
    }

    /// Persists `on` as the desired login-item state and applies it via
    /// `LoginItem.apply`. Returns the thrown error's description for
    /// Settings to show inline, or `nil` on success.
    @discardableResult
    func applyStartAtLogin(_ on: Bool) -> String? {
        prefs.startAtLogin = on
        do {
            try LoginItem.apply(on)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Persists `bindings`, re-registers them with the Hot Key Manager,
    /// and refreshes the status menu's compatibility lines to match
    /// (Settings' hotkey recorders and "Reset to defaults").
    @discardableResult
    func applyHotkeys(_ bindings: [HotkeyAction: HotkeyBinding]) -> Set<HotkeyAction> {
        prefs.hotkeys = bindings
        failedHotkeys = hotkeyCenter?.register(bindings) ?? []
        recompute()
        onCompatibilityChanged?()
        return failedHotkeys
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

        if preview.openSettings {
            showSettings()
            if let path = preview.snapshotPath, let model = settingsModel {
                DispatchQueue.main.async {
                    // `ImageRenderer` shows a placeholder, not its real
                    // content, for the font sample's `NSViewRepresentable`
                    // (every other section renders correctly); the same
                    // `GlyphDrawing.drawCentred` call it makes is already
                    // checked for clean marks via the keyboard panel's own
                    // `--snapshot`.
                    let ok = Self.writeSwiftUISnapshot(SettingsView(model: model).sections.frame(width: 460), to: path)
                    if ok { NSApp.terminate(nil) } else { exit(1) }
                }
            }
            return
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

    /// Renders a SwiftUI view (used for the Settings window) straight to a
    /// PNG via `ImageRenderer` — the content isn't drawn through
    /// `-drawRect:` or a plain `CALayer`, so capturing its hosting window
    /// (`cacheDisplay`, `CALayer.render(in:)`) comes back blank; rendering
    /// the view itself is the documented way around that.
    private static func writeSwiftUISnapshot(_ view: some View, to path: String) -> Bool {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return false }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
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
/// `--preview-mode plain|shift|caps`, `--font "<family>"`,
/// `--open-settings` (show the Settings window instead of the panel), and
/// `--snapshot <png path>` (render the keyboard, or the Settings window
/// with `--open-settings`, offscreen, then quit).
private struct PreviewOptions {
    var mode: DisplayMode = .thai(.plain)
    var shiftHeld = false
    var fontFamily: String?
    var snapshotPath: String?
    var openSettings = false
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
        openSettings = arguments.contains("--open-settings")
        isActive = ["--preview-mode", "--font", "--snapshot", "--open-settings"].contains { arguments.contains($0) }
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
