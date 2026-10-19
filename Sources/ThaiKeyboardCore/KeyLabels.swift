/// The four states a character key can be typed in: combinations of Shift
/// and Caps Lock.
public enum KeyState: CaseIterable, Sendable {
    case plain, shift, caps, capsShift
}

/// Something that can translate a key code and modifier state into the
/// characters a keyboard layout produces for it. Abstracts over the live
/// system layout (`SystemLayout`) so `LabelTable`'s rules can be tested
/// with a fake, per the rule that labels always come from the live layout,
/// never a hardcoded table.
public protocol KeyTranslator: Sendable {
    func characters(keyCode: UInt16, state: KeyState) -> String
}

/// The labels for a set of character keys, for all four `KeyState`s, read
/// once from a `KeyTranslator`.
public struct LabelTable: Sendable {
    private let labels: [UInt16: [KeyState: String]]

    /// `true` when Caps Lock changes what at least one key types (not just
    /// its case), i.e. some key's `.caps` label differs from its `.plain`
    /// label.
    public let capsChangesOutput: Bool

    public init(translator: KeyTranslator, keyCodes: [UInt16]) {
        var labels: [UInt16: [KeyState: String]] = [:]
        var capsChangesOutput = false
        for keyCode in keyCodes {
            var perState: [KeyState: String] = [:]
            for state in KeyState.allCases {
                perState[state] = Self.blankIfControlOnly(translator.characters(keyCode: keyCode, state: state))
            }
            if perState[.caps] != perState[.plain] {
                capsChangesOutput = true
            }
            labels[keyCode] = perState
        }
        self.labels = labels
        self.capsChangesOutput = capsChangesOutput
    }

    /// The label for `keyCode` in `state`, or `""` if the layout gives
    /// nothing or only control characters.
    public func label(_ keyCode: UInt16, _ state: KeyState) -> String {
        labels[keyCode]?[state] ?? ""
    }

    private static func blankIfControlOnly(_ s: String) -> String {
        guard !s.isEmpty, !s.unicodeScalars.allSatisfy({ $0.properties.generalCategory == .control }) else {
            return ""
        }
        return s
    }
}

/// What the keyboard panel should currently show for a character key.
public enum DisplayMode: Equatable, Sendable {
    /// Show the Thai layout's label for `KeyState`.
    case thai(KeyState)
    /// Caps Lock changes output and the user has opted to see it: show
    /// what Caps Lock actually types.
    case capsOutput(KeyState)
    /// Caps Lock changes output and the user hasn't opted in: hide the
    /// panel rather than show a misleading Thai label.
    case hiddenForCaps
}

/// Picks the panel's `DisplayMode` from the live Shift/Caps Lock state.
///
/// Caps Lock is ignored entirely when it doesn't change what a key types
/// (a layout where Caps Lock only affects Latin case, which looks
/// identical in Thai). When it does change output, the panel hides by
/// default rather than show a stale Thai label, until `showCapsOutput`
/// opts in to seeing what Caps Lock actually types.
public func displayMode(shift: Bool, capsLock: Bool, capsChangesOutput: Bool, showCapsOutput: Bool) -> DisplayMode {
    guard capsLock, capsChangesOutput else {
        return .thai(shift ? .shift : .plain)
    }
    guard showCapsOutput else {
        return .hiddenForCaps
    }
    return .capsOutput(shift ? .capsShift : .caps)
}
