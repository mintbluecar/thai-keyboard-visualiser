import Carbon
import Foundation

/// Calls `onChange` on the main actor whenever the selected keyboard input
/// source changes (menu, Globe key, shortcut, or programmatically).
final class InputSourceObserver {
    private let token: NSObjectProtocol

    init(onChange: @escaping @MainActor () -> Void) {
        token = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                onChange()
            }
        }
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(token)
    }
}
