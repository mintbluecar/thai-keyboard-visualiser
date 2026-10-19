import CoreGraphics
import Foundation

/// Persists the user's settings to a `UserDefaults` suite, under keys
/// namespaced "ThaiKeyboard.*" so they can't collide with anything else in
/// the suite. Every property persists immediately on set, and a missing or
/// corrupt stored value reads back as the documented default rather than
/// crashing or throwing.
public final class Preferences {
    private enum Key {
        static let fontFamily = "ThaiKeyboard.fontFamily"
        static let opacity = "ThaiKeyboard.opacity"
        static let frame = "ThaiKeyboard.frame"
        static let showCapsOutput = "ThaiKeyboard.showCapsOutput"
        static let startAtLogin = "ThaiKeyboard.startAtLogin"
        static let hotkeys = "ThaiKeyboard.hotkeys"
    }

    private static let minOpacity: Double = 0.2
    private static let maxOpacity: Double = 1.0

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `nil` means the system Thai font.
    public var fontFamily: String? {
        get { defaults.string(forKey: Key.fontFamily) }
        set { defaults.set(newValue, forKey: Key.fontFamily) }
    }

    /// Clamped to `0.2...1.0` on both read and write.
    public var opacity: Double {
        get {
            guard let value = defaults.object(forKey: Key.opacity) as? Double else { return 0.9 }
            return Self.clampOpacity(value)
        }
        set { defaults.set(Self.clampOpacity(newValue), forKey: Key.opacity) }
    }

    /// `nil` means no frame has been saved yet.
    public var frame: CGRect? {
        get {
            guard let parts = defaults.object(forKey: Key.frame) as? [Double], parts.count == 4 else { return nil }
            return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.frame)
                return
            }
            let parts = [newValue.origin.x, newValue.origin.y, newValue.width, newValue.height]
            defaults.set(parts, forKey: Key.frame)
        }
    }

    public var showCapsOutput: Bool {
        get { defaults.object(forKey: Key.showCapsOutput) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.showCapsOutput) }
    }

    public var startAtLogin: Bool {
        get { defaults.object(forKey: Key.startAtLogin) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.startAtLogin) }
    }

    /// Stored as JSON-encoded data, keyed by `HotkeyAction.rawValue`.
    public var hotkeys: [HotkeyAction: HotkeyBinding] {
        get {
            guard let data = defaults.data(forKey: Key.hotkeys),
                  let decoded = try? JSONDecoder().decode([String: HotkeyBinding].self, from: data)
            else { return Hotkeys.defaults }

            var result: [HotkeyAction: HotkeyBinding] = [:]
            for (rawValue, binding) in decoded {
                guard let action = HotkeyAction(rawValue: rawValue) else { continue }
                result[action] = binding
            }
            return result.isEmpty ? Hotkeys.defaults : result
        }
        set {
            let keyed = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) })
            guard let data = try? JSONEncoder().encode(keyed) else { return }
            defaults.set(data, forKey: Key.hotkeys)
        }
    }

    private static func clampOpacity(_ value: Double) -> Double {
        if value < minOpacity { return minOpacity }
        if value > maxOpacity { return maxOpacity }
        return value
    }
}
