import Observation
import ThaiKeyboardCore

/// Bridges `SettingsView` to `Preferences` and `AppController`: holds the
/// values Settings shows, and applies every change immediately through the
/// controller (which also persists it via `Preferences`).
@MainActor
@Observable
final class SettingsModel {
    private unowned let controller: AppController

    /// `thaiCapableFamilies()` for the font picker; "System Thai" is
    /// represented by `fontFamily == nil` and added by `SettingsView`.
    let thaiFamilies: [String]

    var fontFamily: String?
    /// 20...100.
    var opacityPercent: Double
    /// 25...100, the panel's width as a percentage of its screen.
    var sizePercent: Double
    var showCapsOutput: Bool
    var startAtLogin: Bool
    /// The error text to show inline under the login toggle, if any —
    /// either a kept first-launch failure or the last toggle's failure.
    var startAtLoginError: String?
    var hotkeys: [HotkeyAction: HotkeyBinding]
    var failedHotkeys: Set<HotkeyAction>
    var compatibilityLines: [String] = []

    init(controller: AppController) {
        self.controller = controller
        thaiFamilies = FontResolver.thaiCapableFamilies()
        fontFamily = controller.prefs.fontFamily
        opacityPercent = controller.prefs.opacity * 100
        sizePercent = controller.currentSizePercent() * 100
        showCapsOutput = controller.prefs.showCapsOutput
        startAtLogin = controller.prefs.startAtLogin
        startAtLoginError = controller.firstLaunchLoginItemError?.localizedDescription
        hotkeys = controller.prefs.hotkeys
        failedHotkeys = controller.failedHotkeys

        controller.onCompatibilityChanged = { [weak self] in self?.refreshCompatibility() }
        refreshCompatibility()
    }

    /// Re-reads `compatibilityReport().lines`. Called when the Settings
    /// window opens and whenever `AppController` says something that
    /// affects the report might have changed (input source, hotkeys,
    /// permissions). Only assigns when the lines actually changed, so
    /// `@Observable` doesn't notify `SettingsView` for no reason.
    func refreshCompatibility() {
        let lines = controller.compatibilityReport().lines
        guard lines != compatibilityLines else { return }
        compatibilityLines = lines
    }

    /// Re-reads everything that can drift out from under Settings while
    /// its window isn't the one changing it — the size slider (a hotkey
    /// resize or a drag moves the panel without touching the model) and
    /// which hotkeys are currently failing — plus the compatibility
    /// section. Called every time the window is (re)shown.
    func refresh() {
        sizePercent = controller.currentSizePercent() * 100
        failedHotkeys = controller.failedHotkeys
        refreshCompatibility()
    }

    func setFontFamily(_ family: String?) {
        fontFamily = family
        controller.applyFontFamily(family)
    }

    func setOpacityPercent(_ percent: Double) {
        opacityPercent = percent
        controller.applyOpacity(percent / 100)
    }

    func setSizePercent(_ percent: Double) {
        sizePercent = percent
        controller.applySizePercent(percent / 100)
    }

    func setShowCapsOutput(_ show: Bool) {
        showCapsOutput = show
        controller.applyShowCapsOutput(show)
    }

    func setStartAtLogin(_ on: Bool) {
        startAtLogin = on
        startAtLoginError = controller.applyStartAtLogin(on)
    }

    func setBinding(_ binding: HotkeyBinding, for action: HotkeyAction) {
        hotkeys[action] = binding
        failedHotkeys = controller.applyHotkeys(hotkeys)
    }

    func resetHotkeysToDefaults() {
        hotkeys = Hotkeys.defaults
        failedHotkeys = controller.applyHotkeys(hotkeys)
    }
}
