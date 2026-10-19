import AppKit

/// Owns the app's top-level UI. Held strongly for the lifetime of the app.
@MainActor
final class AppController {
    private let statusMenu: StatusMenu

    init() {
        statusMenu = StatusMenu(onQuit: {
            NSApp.terminate(nil)
        })
    }
}
