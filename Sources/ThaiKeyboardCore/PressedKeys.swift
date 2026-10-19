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

    /// `true` while any key, Shift or Caps Lock is on, i.e. while a missed
    /// event (key-ups and flag changes aren't delivered to event taps under
    /// Secure Event Input) could leave something wrongly lit or the panel
    /// wrongly hidden, so the caller should keep checking against the
    /// system's own key state.
    public var needsReconcile: Bool {
        !keys.isEmpty || shift || capsLock
    }

    /// Drops every held key that `isDown` (the system's key state) says is
    /// no longer down. Never adds keys: a press only counts once its event
    /// arrives.
    public mutating func reconcile(isDown: (UInt16) -> Bool) {
        keys = keys.filter(isDown)
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
