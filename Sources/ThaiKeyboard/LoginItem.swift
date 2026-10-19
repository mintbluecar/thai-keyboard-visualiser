import ServiceManagement

/// Registers (or unregisters) ThaiKeyboard as a login item via
/// `SMAppService.mainApp`.
enum LoginItem {
    static func apply(_ on: Bool) throws {
        let service = SMAppService.mainApp
        if on {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status == .enabled else { return }
            try service.unregister()
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
