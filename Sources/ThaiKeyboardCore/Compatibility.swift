/// A snapshot of everything that affects whether the app works as expected
/// right now, turned into the lines the status menu shows and the subset
/// of those lines that need the user to act.
public struct CompatibilityReport: Equatable, Sendable {
    public let inputSource: InputSourceInfo
    public let keyboardType: KeyboardType
    public let inputMonitoring: Bool
    public let capsChangesOutput: Bool
    public let failedHotkeys: Set<HotkeyAction>

    public init(
        inputSource: InputSourceInfo,
        keyboardType: KeyboardType,
        inputMonitoring: Bool,
        capsChangesOutput: Bool,
        failedHotkeys: Set<HotkeyAction>
    ) {
        self.inputSource = inputSource
        self.keyboardType = keyboardType
        self.inputMonitoring = inputMonitoring
        self.capsChangesOutput = capsChangesOutput
        self.failedHotkeys = failedHotkeys
    }

    /// The exact text of the "Key presses: not allowed" line, shared with
    /// `AppController` so it can recognise which action item opens the
    /// Input Monitoring pane rather than matching a duplicated literal.
    public static let keyPressesNotAllowedLine =
        "Key presses: not allowed — grant Input Monitoring in System Settings"

    /// All applicable lines, in a fixed order: input source, keyboard
    /// match, key press permission, Caps Lock behaviour, and — only when
    /// some are set — the hotkeys currently held by another app.
    public var lines: [String] {
        var result = [inputSourceLine, keyboardLine, keyPressesLine, capsLockLine]
        if let failedHotkeysLine { result.append(failedHotkeysLine) }
        return result
    }

    /// The subset of `lines` that tell the user something they can act on:
    /// a non-ANSI keyboard, a missing permission, or a hotkey taken by
    /// another app. Never the input source or Caps Lock lines, since
    /// there's nothing to do about either from the menu.
    public var actionItems: [String] {
        var result: [String] = []
        if keyboardType != .ansi { result.append(keyboardLine) }
        if !inputMonitoring { result.append(keyPressesLine) }
        if let failedHotkeysLine { result.append(failedHotkeysLine) }
        return result
    }

    private var inputSourceLine: String {
        inputSource.isThai
            ? "Input source: \(inputSource.name) — counts as Thai"
            : "Input source: \(inputSource.name) — not Thai, keyboard hidden"
    }

    private var keyboardLine: String {
        guard keyboardType != .ansi else { return "Keyboard: MacBook (ANSI) — matches" }
        return "Keyboard: \(Self.keyboardTypeName(keyboardType)) — drawn as MacBook ANSI, may not match your keys"
    }

    private var keyPressesLine: String {
        inputMonitoring ? "Key presses: allowed" : Self.keyPressesNotAllowedLine
    }

    private var capsLockLine: String {
        capsChangesOutput
            ? "Caps Lock: types different characters in this layout"
            : "Caps Lock: no effect in this layout"
    }

    /// `nil` when nothing failed; otherwise the failed actions' titles,
    /// comma-separated in `HotkeyAction.allCases` order.
    private var failedHotkeysLine: String? {
        guard !failedHotkeys.isEmpty else { return nil }
        let titles = HotkeyAction.allCases.filter(failedHotkeys.contains).map(\.title)
        return "Hotkeys in use by another app: \(titles.joined(separator: ", "))"
    }

    private static func keyboardTypeName(_ type: KeyboardType) -> String {
        switch type {
        case .ansi: return "ANSI"
        case .iso: return "ISO"
        case .jis: return "JIS"
        case .unknown: return "unknown"
        }
    }
}
