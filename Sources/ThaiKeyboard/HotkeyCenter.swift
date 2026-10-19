import Carbon.HIToolbox
import ThaiKeyboardCore

/// Registers the user's global hotkeys with Carbon's Hot Key Manager and
/// dispatches presses back onto the main actor. The only place in the app
/// target that talks to the Hot Key Manager directly.
@MainActor
final class HotkeyCenter {
    /// Four-char creator code ("THKB") distinguishing this app's hotkeys.
    private static let signature: UInt32 = 0x54484B42

    private let context: HotkeyContext
    private var eventHandlerRef: EventHandlerRef?
    private var nextID: UInt32 = 1

    init(onAction: @escaping @MainActor (HotkeyAction) -> Void) {
        context = HotkeyContext(onAction: onAction)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyPressedHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(context).toOpaque(),
            &eventHandlerRef
        )
    }

    /// Unregisters whatever's currently registered, then registers each of
    /// `bindings`. Returns the actions that failed to register (e.g.
    /// because another app already holds that key combination).
    @discardableResult
    func register(_ bindings: [HotkeyAction: HotkeyBinding]) -> Set<HotkeyAction> {
        context.unregisterAll()

        var failed: Set<HotkeyAction> = []
        for (action, binding) in bindings {
            let id = nextID
            nextID += 1
            var hotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(
                binding.keyCode,
                binding.carbonModifiers,
                EventHotKeyID(signature: Self.signature, id: id),
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr, let hotKeyRef {
                context.register(id: id, ref: hotKeyRef, action: action)
            } else {
                failed.insert(action)
            }
        }
        return failed
    }
}

/// What the C event handler callback reaches through its `userData`
/// pointer: the live hotkey registrations and the action to run for each.
/// Mutated only from the main actor (via `HotkeyCenter.register`) and read
/// only from Carbon's callback on the main run loop, so never actually
/// concurrent despite the `@unchecked Sendable`.
private final class HotkeyContext: @unchecked Sendable {
    private let onAction: @MainActor (HotkeyAction) -> Void
    private var registered: [UInt32: (ref: EventHotKeyRef, action: HotkeyAction)] = [:]

    init(onAction: @escaping @MainActor (HotkeyAction) -> Void) {
        self.onAction = onAction
    }

    func register(id: UInt32, ref: EventHotKeyRef, action: HotkeyAction) {
        registered[id] = (ref, action)
    }

    func unregisterAll() {
        for (_, entry) in registered {
            UnregisterEventHotKey(entry.ref)
        }
        registered.removeAll()
    }

    /// Hands the action for `id` to the main actor without waiting, so the
    /// Carbon callback returns immediately.
    func fire(id: UInt32) {
        guard let action = registered[id]?.action else { return }
        let onAction = self.onAction
        DispatchQueue.main.async {
            onAction(action)
        }
    }
}

/// Runs on Carbon's main-run-loop callback. Pulls the hotkey ID out of the
/// event and hands it to the matching `HotkeyContext`.
private let hotkeyPressedHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return OSStatus(eventNotHandledErr) }
    let context = Unmanaged<HotkeyContext>.fromOpaque(userData).takeUnretainedValue()
    context.fire(id: hotKeyID.id)
    return noErr
}
