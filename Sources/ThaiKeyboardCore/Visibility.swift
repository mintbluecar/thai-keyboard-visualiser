/// Whether the keyboard panel should be shown: driven by the current input
/// source, a manual hide/show from the user, and a transient hide while
/// Caps Lock output is on screen instead of Thai.
public struct Visibility: Equatable, Sendable {
    private var isThai: Bool

    /// `true` once the user has explicitly hidden the panel, until the
    /// input source changes (even to another Thai source) or the user
    /// shows it again.
    public private(set) var userHidden: Bool

    /// `true` once the user has explicitly shown the panel: it then shows
    /// whatever the input source or Caps Lock, so Show never seems to do
    /// nothing. Lasts until the user hides it or the input source changes.
    public private(set) var userShown: Bool

    public init(isThai: Bool) {
        self.isThai = isThai
        self.userHidden = false
        self.userShown = false
    }

    /// Call whenever the active input source changes. Always clears a
    /// user hide or show, even when switching between two Thai sources.
    public mutating func inputSourceChanged(isThai: Bool) {
        self.isThai = isThai
        self.userHidden = false
        self.userShown = false
    }

    public mutating func userHide() {
        userHidden = true
        userShown = false
    }

    public mutating func userShow() {
        userHidden = false
        userShown = true
    }

    /// `true` when the user chose Show, or when the input source is Thai,
    /// the user hasn't hidden the panel, and it isn't currently hidden to
    /// show what Caps Lock types.
    public func isVisible(hiddenForCaps: Bool) -> Bool {
        userShown || (isThai && !userHidden && !hiddenForCaps)
    }
}
