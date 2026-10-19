import Carbon.HIToolbox
import CoreGraphics

/// What a key is, for layout and drawing purposes: a character key (its
/// label comes from the live input source) or a modifier/function key with
/// a fixed, small grey label.
public enum KeyKind: Equatable, Sendable {
    case character
    case modifier(String)
}

/// One key's position and identity on the keyboard panel.
///
/// `rect` is in key units: 1.0 = one standard key, y grows downward, and
/// gaps between keys are not included in the rect.
public struct KeySpec: Equatable, Sendable {
    public let keyCode: UInt16
    public let rect: CGRect
    public let kind: KeyKind

    public init(keyCode: UInt16, rect: CGRect, kind: KeyKind) {
        self.keyCode = keyCode
        self.rect = rect
        self.kind = kind
    }
}

/// The geometry of a MacBook ANSI keyboard (no function row), in key units.
public enum MacBookANSI {
    /// Every key on the keyboard, positioned in key units.
    public static let keys: [KeySpec] = row0 + row1 + row2 + row3 + row4

    /// The overall size of the keyboard, in key units: 14.5 wide, 5 tall.
    public static let unitSize = CGSize(width: 14.5, height: 5)

    /// The `keyCode` of every character key, i.e. every key whose label
    /// comes from the live input source rather than a fixed modifier label.
    public static var characterKeyCodes: [UInt16] {
        keys.filter { $0.kind == .character }.map(\.keyCode)
    }

    // Row 0: ` 1 2 3 4 5 6 7 8 9 0 - =, delete.
    private static let row0: [KeySpec] = {
        let codes: [UInt16] = [
            UInt16(kVK_ANSI_Grave), UInt16(kVK_ANSI_1), UInt16(kVK_ANSI_2), UInt16(kVK_ANSI_3), UInt16(kVK_ANSI_4),
            UInt16(kVK_ANSI_5), UInt16(kVK_ANSI_6), UInt16(kVK_ANSI_7), UInt16(kVK_ANSI_8), UInt16(kVK_ANSI_9),
            UInt16(kVK_ANSI_0), UInt16(kVK_ANSI_Minus), UInt16(kVK_ANSI_Equal),
        ]
        var result = characterRow(codes: codes, y: 0, startX: 0)
        result.append(KeySpec(
            keyCode: UInt16(kVK_Delete),
            rect: CGRect(x: 13, y: 0, width: 1.5, height: 1),
            kind: .modifier("delete")
        ))
        return result
    }()

    // Row 1: tab, Q W E R T Y U I O P [ ] \.
    private static let row1: [KeySpec] = {
        let codes: [UInt16] = [
            UInt16(kVK_ANSI_Q), UInt16(kVK_ANSI_W), UInt16(kVK_ANSI_E), UInt16(kVK_ANSI_R), UInt16(kVK_ANSI_T),
            UInt16(kVK_ANSI_Y), UInt16(kVK_ANSI_U), UInt16(kVK_ANSI_I), UInt16(kVK_ANSI_O), UInt16(kVK_ANSI_P),
            UInt16(kVK_ANSI_LeftBracket), UInt16(kVK_ANSI_RightBracket), UInt16(kVK_ANSI_Backslash),
        ]
        var result: [KeySpec] = [KeySpec(
            keyCode: UInt16(kVK_Tab),
            rect: CGRect(x: 0, y: 1, width: 1.5, height: 1),
            kind: .modifier("tab")
        )]
        result.append(contentsOf: characterRow(codes: codes, y: 1, startX: 1.5))
        return result
    }()

    // Row 2: caps, A S D F G H J K L ; ', return.
    private static let row2: [KeySpec] = {
        let codes: [UInt16] = [
            UInt16(kVK_ANSI_A), UInt16(kVK_ANSI_S), UInt16(kVK_ANSI_D), UInt16(kVK_ANSI_F), UInt16(kVK_ANSI_G),
            UInt16(kVK_ANSI_H), UInt16(kVK_ANSI_J), UInt16(kVK_ANSI_K), UInt16(kVK_ANSI_L), UInt16(kVK_ANSI_Semicolon),
            UInt16(kVK_ANSI_Quote),
        ]
        var result: [KeySpec] = [KeySpec(
            keyCode: UInt16(kVK_CapsLock),
            rect: CGRect(x: 0, y: 2, width: 1.75, height: 1),
            kind: .modifier("caps")
        )]
        result.append(contentsOf: characterRow(codes: codes, y: 2, startX: 1.75))
        result.append(KeySpec(
            keyCode: UInt16(kVK_Return),
            rect: CGRect(x: 12.75, y: 2, width: 1.75, height: 1),
            kind: .modifier("return")
        ))
        return result
    }()

    // Row 3: shift, Z X C V B N M , . /, shift.
    private static let row3: [KeySpec] = {
        let codes: [UInt16] = [
            UInt16(kVK_ANSI_Z), UInt16(kVK_ANSI_X), UInt16(kVK_ANSI_C), UInt16(kVK_ANSI_V), UInt16(kVK_ANSI_B),
            UInt16(kVK_ANSI_N), UInt16(kVK_ANSI_M), UInt16(kVK_ANSI_Comma), UInt16(kVK_ANSI_Period), UInt16(kVK_ANSI_Slash),
        ]
        var result: [KeySpec] = [KeySpec(
            keyCode: UInt16(kVK_Shift),
            rect: CGRect(x: 0, y: 3, width: 2.25, height: 1),
            kind: .modifier("shift")
        )]
        result.append(contentsOf: characterRow(codes: codes, y: 3, startX: 2.25))
        result.append(KeySpec(
            keyCode: UInt16(kVK_RightShift),
            rect: CGRect(x: 12.25, y: 3, width: 2.25, height: 1),
            kind: .modifier("shift")
        ))
        return result
    }()

    // Row 4: fn, control, option, command, space, command, option, ◀, ▲ over ▼, ▶.
    private static let row4: [KeySpec] = [
        KeySpec(
            keyCode: UInt16(kVK_Function),
            rect: CGRect(x: 0, y: 4, width: 1, height: 1),
            kind: .modifier("fn")
        ),
        KeySpec(
            keyCode: UInt16(kVK_Control),
            rect: CGRect(x: 1, y: 4, width: 1, height: 1),
            kind: .modifier("control")
        ),
        KeySpec(
            keyCode: UInt16(kVK_Option),
            rect: CGRect(x: 2, y: 4, width: 1, height: 1),
            kind: .modifier("option")
        ),
        KeySpec(
            keyCode: UInt16(kVK_Command),
            rect: CGRect(x: 3, y: 4, width: 1.25, height: 1),
            kind: .modifier("command")
        ),
        KeySpec(
            keyCode: UInt16(kVK_Space),
            rect: CGRect(x: 4.25, y: 4, width: 5, height: 1),
            kind: .modifier("")
        ),
        KeySpec(
            keyCode: UInt16(kVK_RightCommand),
            rect: CGRect(x: 9.25, y: 4, width: 1.25, height: 1),
            kind: .modifier("command")
        ),
        KeySpec(
            keyCode: UInt16(kVK_RightOption),
            rect: CGRect(x: 10.5, y: 4, width: 1, height: 1),
            kind: .modifier("option")
        ),
        KeySpec(
            keyCode: UInt16(kVK_LeftArrow),
            rect: CGRect(x: 11.5, y: 4, width: 1, height: 1),
            kind: .modifier("◀")
        ),
        KeySpec(
            keyCode: UInt16(kVK_UpArrow),
            rect: CGRect(x: 12.5, y: 4, width: 1, height: 0.5),
            kind: .modifier("▲")
        ),
        KeySpec(
            keyCode: UInt16(kVK_DownArrow),
            rect: CGRect(x: 12.5, y: 4.5, width: 1, height: 0.5),
            kind: .modifier("▼")
        ),
        KeySpec(
            keyCode: UInt16(kVK_RightArrow),
            rect: CGRect(x: 13.5, y: 4, width: 1, height: 1),
            kind: .modifier("▶")
        ),
    ]

    /// Builds a row of 1×1 character keys, one per code in `codes`, laid
    /// out left to right starting at `startX`.
    private static func characterRow(codes: [UInt16], y: CGFloat, startX: CGFloat) -> [KeySpec] {
        codes.enumerated().map { index, code in
            KeySpec(
                keyCode: code,
                rect: CGRect(x: startX + CGFloat(index), y: y, width: 1, height: 1),
                kind: .character
            )
        }
    }
}
