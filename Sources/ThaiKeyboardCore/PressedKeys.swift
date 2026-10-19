/// The keys currently held down, plus Shift and Caps Lock, as reported by
/// the live key event stream.
public struct PressedKeys: Equatable, Sendable {
    public private(set) var keys: Set<UInt16> = []
    public private(set) var shift = false
    public private(set) var capsLock = false

    public init() {}

    public mutating func keyDown(_ code: UInt16) {
        keys.insert(code)
    }

    public mutating func keyUp(_ code: UInt16) {
        keys.remove(code)
    }

    /// Takes Shift and Caps Lock straight from the event's modifier flags
    /// rather than counting presses, so a missed event can't leave them
    /// stuck.
    public mutating func flagsChanged(shift: Bool, capsLock: Bool) {
        self.shift = shift
        self.capsLock = capsLock
    }

    /// Clears held keys and Shift, e.g. when the input source changes or
    /// the panel is shown, so nothing lit before stays lit. Caps Lock is a
    /// latched state, not a held key, so it is kept; the next flags event
    /// resyncs it anyway.
    public mutating func reset() {
        keys = []
        shift = false
    }
}
