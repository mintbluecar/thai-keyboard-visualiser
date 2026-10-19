import AppKit
import Carbon.HIToolbox
import SwiftUI
import ThaiKeyboardCore

/// Renders a `HotkeyBinding` as the symbols System Settings uses (e.g.
/// "⌃⌥←"), and a small fixed table translating key codes to names for the
/// US layout, since `Hotkeys.defaults` and anything the recorder below can
/// produce are always US-layout key codes.
enum HotkeyDisplay {
    static func string(for binding: HotkeyBinding) -> String {
        modifierSymbols(binding.carbonModifiers) + keyName(for: binding.keyCode)
    }

    static func modifierSymbols(_ carbonModifiers: UInt32) -> String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result
    }

    private static func keyName(for keyCode: UInt32) -> String {
        if let name = names[Int(keyCode)] { return name }
        return "Key \(keyCode)"
    }

    private static let names: [Int: String] = {
        var pairs: [(Int, String)] = [
            (kVK_LeftArrow, "←"), (kVK_RightArrow, "→"), (kVK_UpArrow, "↑"), (kVK_DownArrow, "↓"),
            (kVK_Space, "Space"), (kVK_Return, "Return"), (kVK_Tab, "Tab"),
            (kVK_Delete, "Delete"), (kVK_Escape, "Esc"),
            (kVK_ANSI_Grave, "`"), (kVK_ANSI_Minus, "−"), (kVK_ANSI_Equal, "="),
            (kVK_ANSI_LeftBracket, "["), (kVK_ANSI_RightBracket, "]"), (kVK_ANSI_Backslash, "\\"),
            (kVK_ANSI_Semicolon, ";"), (kVK_ANSI_Quote, "'"),
            (kVK_ANSI_Comma, ","), (kVK_ANSI_Period, "."), (kVK_ANSI_Slash, "/"),
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"), (kVK_ANSI_4, "4"),
            (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
        ]
        let letters: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"), (kVK_ANSI_E, "E"),
            (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"), (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"),
            (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"), (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"),
            (kVK_ANSI_P, "P"), (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"), (kVK_ANSI_Y, "Y"),
            (kVK_ANSI_Z, "Z"),
        ]
        pairs.append(contentsOf: letters)
        return Dictionary(uniqueKeysWithValues: pairs)
    }()
}

/// One hotkey's row: its name, a button that shows the current binding
/// (or "Record") and records the next qualifying key press, and any
/// failure note.
struct HotkeyRow: View {
    let action: HotkeyAction
    let model: SettingsModel

    @State private var isRecording = false
    @State private var hint: String?
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(action.title)
                .frame(width: 150, alignment: .leading)

            Spacer()

            if isRecording {
                Text(hint ?? "Press a key with ⌃, ⌥ or ⌘ — Esc cancels")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.failedHotkeys.contains(action) {
                Text("In use by another app — choose another")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(isRecording ? "Recording…" : displayString) {
                startRecording()
            }
            .disabled(isRecording)
            .frame(width: 100)
        }
        .onDisappear { stopRecording() }
    }

    private var displayString: String {
        guard let binding = model.hotkeys[action] else { return "Record" }
        return HotkeyDisplay.string(for: binding)
    }

    private func startRecording() {
        isRecording = true
        hint = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    /// Esc cancels. Otherwise, at least one of ⌃⌥⌘ is required (Shift
    /// alone isn't, so the recorder can't be mistaken for a plain Shift
    /// press); without one, a hint is shown and recording continues.
    private func handle(_ event: NSEvent) {
        guard event.keyCode != UInt16(kVK_Escape) else {
            hint = nil
            stopRecording()
            return
        }

        let flags = event.modifierFlags.intersection([.control, .option, .command, .shift])
        guard !flags.intersection([.control, .option, .command]).isEmpty else {
            hint = "Hold ⌃, ⌥ or ⌘ with the key"
            return
        }

        var carbonModifiers: UInt32 = 0
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

        let binding = HotkeyBinding(keyCode: UInt32(event.keyCode), carbonModifiers: carbonModifiers)
        hint = nil
        stopRecording()
        model.setBinding(binding, for: action)
    }
}
