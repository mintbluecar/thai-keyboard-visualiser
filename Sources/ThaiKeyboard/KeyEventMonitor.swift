import AppKit
import CoreGraphics

/// Watches key presses system-wide through a listen-only `CGEventTap`
/// (needs the Input Monitoring permission) and reports them on the main
/// actor. Events are only turned into `KeyEvent`s and passed on; nothing
/// about them is logged or stored.
@MainActor
final class KeyEventMonitor {
    enum KeyEvent: Sendable {
        case down(UInt16)
        case up(UInt16)
        case flags(shift: Bool, capsLock: Bool)
    }

    /// Called on the main actor once the tap is running.
    var onStarted: (() -> Void)?

    private static let retryInterval: TimeInterval = 2
    private static let requestedAccessKey = "local.thaikeyboard.app.didRequestListenEventAccess"

    private let context: TapContext
    private var retryTimer: Timer?
    private var isRunning = false

    init(onEvent: @escaping @MainActor (KeyEvent) -> Void) {
        context = TapContext(onEvent: onEvent)
    }

    /// `true` once the tap is running, or the system reports the Input
    /// Monitoring permission as granted.
    var hasPermission: Bool {
        isRunning || CGPreflightListenEventAccess()
    }

    /// Starts the tap, asking for Input Monitoring the first time the app
    /// ever launches without it. If the tap can't be created yet (no
    /// permission), retries every 2 s until it can, so a permission
    /// granted while the app runs takes effect without a relaunch.
    func start() {
        guard !isRunning, retryTimer == nil else { return }
        requestAccessOnce()
        if tryCreateTap() { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: Self.retryInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.tryCreateTap() else { return }
                self.retryTimer?.invalidate()
                self.retryTimer = nil
            }
        }
    }

    private func requestAccessOnce() {
        let defaults = UserDefaults.standard
        guard !CGPreflightListenEventAccess(), !defaults.bool(forKey: Self.requestedAccessKey) else { return }
        defaults.set(true, forKey: Self.requestedAccessKey)
        _ = CGRequestListenEventAccess()
    }

    /// Creates the tap and runs it on its own thread, so a busy main thread
    /// never stalls the tap. Returns `false` if the system refused (no
    /// permission yet). Without Input Monitoring the system may still hand
    /// back a tap, but a disabled one that can't be enabled, so a tap only
    /// counts once it is enabled.
    private func tryCreateTap() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(context).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            CFMachPortInvalidate(tap)
            return false
        }
        context.tap = tap
        let runLoopSource = UncheckedSendable(source)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource.value, .commonModes)
            CFRunLoopRun()
        }
        thread.name = "ThaiKeyboard.KeyEventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        isRunning = true
        onStarted?()
        return true
    }
}

/// What the C tap callback can reach through its `userInfo` pointer. Its
/// state is set once on the main actor before the tap thread starts and
/// only read afterwards.
private final class TapContext: @unchecked Sendable {
    let onEvent: @MainActor (KeyEventMonitor.KeyEvent) -> Void
    var tap: CFMachPort?

    init(onEvent: @escaping @MainActor (KeyEventMonitor.KeyEvent) -> Void) {
        self.onEvent = onEvent
    }

    /// Hands `event` to the main actor without waiting, so the tap returns
    /// immediately. `DispatchQueue.main` keeps events in order.
    func deliver(_ event: KeyEventMonitor.KeyEvent) {
        let onEvent = self.onEvent
        DispatchQueue.main.async {
            onEvent(event)
        }
    }
}

private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Runs on the tap's thread. Listen-only: always returns the event
/// unmodified.
private let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<TapContext>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let tap = context.tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    case .keyDown:
        // Auto-repeat doesn't change which keys are held.
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            context.deliver(.down(UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))))
        }
    case .keyUp:
        context.deliver(.up(UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))))
    case .flagsChanged:
        context.deliver(.flags(shift: event.flags.contains(.maskShift), capsLock: event.flags.contains(.maskAlphaShift)))
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}
