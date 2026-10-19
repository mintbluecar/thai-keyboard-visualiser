/// Whether the keyboard panel should be shown: driven by the current input
/// source, a manual hide/show from the user, and a transient hide while
/// Caps Lock output is on screen instead of Thai.
public struct Visibility: Equatable, Sendable {
    private var isThai: Bool

    /// `true` once the user has explicitly hidden the panel, until the
    /// input source changes (even to another Thai source) or the user
    /// shows it again.
    public private(set) var userHidden: Bool

    public init(isThai: Bool) {
        self.isThai = isThai
        self.userHidden = false
    }

    /// Call whenever the active input source changes. Always clears a
    /// user-hide, even when switching between two Thai sources.
    public mutating func inputSourceChanged(isThai: Bool) {
        self.isThai = isThai
        self.userHidden = false
    }

    public mutating func userHide() {
        userHidden = true
    }

    public mutating func userShow() {
        userHidden = false
    }

    /// `true` when the input source is Thai, the user hasn't hidden the
    /// panel, and it isn't currently hidden to show what Caps Lock types.
    public func isVisible(hiddenForCaps: Bool) -> Bool {
        isThai && !userHidden && !hiddenForCaps
    }
}
