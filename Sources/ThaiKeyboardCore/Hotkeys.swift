import Carbon.HIToolbox

/// An action a global hotkey can trigger: snap the panel to an edge or
/// corner of the screen, or resize it.
public enum HotkeyAction: String, CaseIterable, Codable, Sendable {
    case snapTop, snapBottom, snapLeft, snapRight
    case snapTopLeft, snapTopRight, snapBottomLeft, snapBottomRight
    case bigger, smaller
}

/// A key code (`kVK_*`) plus Carbon modifier flags (e.g. `controlKey |
/// optionKey`) identifying a global hotkey.
public struct HotkeyBinding: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }
}

/// The default global hotkeys (Global Constraints): Ctrl+Option plus an
/// arrow key snaps to that edge's centre, U/I/J/K snap to a corner, and
/// =/− resize bigger/smaller.
public enum Hotkeys {
    private static let modifiers = UInt32(controlKey | optionKey)

    public static let defaults: [HotkeyAction: HotkeyBinding] = [
        .snapTop: HotkeyBinding(keyCode: UInt32(kVK_UpArrow), carbonModifiers: modifiers),
        .snapBottom: HotkeyBinding(keyCode: UInt32(kVK_DownArrow), carbonModifiers: modifiers),
        .snapLeft: HotkeyBinding(keyCode: UInt32(kVK_LeftArrow), carbonModifiers: modifiers),
        .snapRight: HotkeyBinding(keyCode: UInt32(kVK_RightArrow), carbonModifiers: modifiers),
        .snapTopLeft: HotkeyBinding(keyCode: UInt32(kVK_ANSI_U), carbonModifiers: modifiers),
        .snapTopRight: HotkeyBinding(keyCode: UInt32(kVK_ANSI_I), carbonModifiers: modifiers),
        .snapBottomLeft: HotkeyBinding(keyCode: UInt32(kVK_ANSI_J), carbonModifiers: modifiers),
        .snapBottomRight: HotkeyBinding(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: modifiers),
        .bigger: HotkeyBinding(keyCode: UInt32(kVK_ANSI_Equal), carbonModifiers: modifiers),
        .smaller: HotkeyBinding(keyCode: UInt32(kVK_ANSI_Minus), carbonModifiers: modifiers),
    ]
}

extension HotkeyAction {
    /// The name shown for this action in Settings and in the compatibility
    /// report's "Hotkeys in use by another app" line.
    public var title: String {
        switch self {
        case .snapTop: return "Snap to top"
        case .snapBottom: return "Snap to bottom"
        case .snapLeft: return "Snap to left"
        case .snapRight: return "Snap to right"
        case .snapTopLeft: return "Snap to top-left"
        case .snapTopRight: return "Snap to top-right"
        case .snapBottomLeft: return "Snap to bottom-left"
        case .snapBottomRight: return "Snap to bottom-right"
        case .bigger: return "Bigger"
        case .smaller: return "Smaller"
        }
    }
}
