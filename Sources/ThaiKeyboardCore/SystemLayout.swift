import Carbon
import Foundation

/// An input source the system knows about.
public struct InputSourceInfo: Equatable, Sendable {
    public let id: String
    public let name: String
    public let isThai: Bool
}

/// The physical keyboard's layout family, from `KBGetLayoutType`.
public enum KeyboardType: Equatable, Sendable {
    case ansi, iso, jis, unknown
}

/// Reads the current input source and keyboard layouts from the system via
/// Carbon/TIS. The only place in this package that talks to Carbon's Text
/// Input Sources API directly; everything else goes through `KeyTranslator`.
public enum SystemLayout {
    /// The currently selected input source.
    public static func current() -> InputSourceInfo {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return InputSourceInfo(id: "", name: "", isThai: false)
        }
        return info(for: source)
    }

    /// A translator for the installed input source with id `sourceID`,
    /// even when it isn't the currently selected one. `nil` if no such
    /// source is installed.
    public static func translator(forSourceID sourceID: String) -> KeyTranslator? {
        guard let source = installedSource(withID: sourceID) else { return nil }
        return CarbonKeyTranslator(source: source)
    }

    /// A translator for the currently selected input source.
    public static func currentTranslator() -> KeyTranslator? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return nil
        }
        return CarbonKeyTranslator(source: source)
    }

    /// The physical keyboard's layout family.
    public static func keyboardType() -> KeyboardType {
        switch Int(KBGetLayoutType(Int16(LMGetKbdType()))) {
        case kKeyboardANSI: return .ansi
        case kKeyboardISO: return .iso
        case kKeyboardJIS: return .jis
        default: return .unknown
        }
    }

    /// `true` when any of `languages` is a Thai language tag, i.e. starts
    /// with "th".
    public static func isThai(languages: [String]) -> Bool {
        languages.contains { $0.hasPrefix("th") }
    }

    private static func installedSource(withID sourceID: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID: sourceID] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        return list.first
    }

    private static func info(for source: TISInputSource) -> InputSourceInfo {
        InputSourceInfo(
            id: stringProperty(source, kTISPropertyInputSourceID) ?? "",
            name: stringProperty(source, kTISPropertyLocalizedName) ?? "",
            isThai: isThai(languages: languages(of: source))
        )
    }

    private static func languages(of source: TISInputSource) -> [String] {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return []
        }
        return (Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as? [String]) ?? []
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}

/// Translates key codes to characters using a keyboard layout's Unicode
/// key layout data via `UCKeyTranslate`. Copies the layout data out of the
/// `TISInputSource` at init into plain `Data`, so the translator stays
/// valid (and `Sendable`) after the source that produced it is released.
private struct CarbonKeyTranslator: KeyTranslator {
    private let layoutData: Data
    private let keyboardType: UInt32

    init?(source: TISInputSource) {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let cfData = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue()
        layoutData = Data(referencing: cfData)
        keyboardType = UInt32(LMGetKbdType())
    }

    func characters(keyCode: UInt16, state: KeyState) -> String {
        layoutData.withUnsafeBytes { raw -> String in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return ""
            }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                state.carbonModifiers,
                keyboardType,
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            guard status == noErr, length > 0 else { return "" }
            return String(utf16CodeUnits: chars, count: length)
        }
    }
}

extension KeyState {
    /// The modifier byte `UCKeyTranslate` expects for this state: the
    /// relevant Carbon modifier flags (`shiftKey` for Shift, `alphaLock`
    /// for Caps Lock), shifted into its keyModifiers byte.
    fileprivate var carbonModifiers: UInt32 {
        switch self {
        case .plain: return 0
        case .shift: return UInt32(shiftKey) >> 8
        case .caps: return UInt32(alphaLock) >> 8
        case .capsShift: return UInt32(shiftKey | alphaLock) >> 8
        }
    }
}
