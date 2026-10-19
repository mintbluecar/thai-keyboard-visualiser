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

    /// Called on the main actor when the tap starts, or stops because it
    /// died (e.g. Input Monitoring was revoked). After a stop, no key-up
    /// will arrive for keys held at the time.
    var onRunningChanged: (() -> Void)?

    private static let checkInterval: TimeInterval = 2
    private static let requestedAccessKey = "local.thaikeyboard.app.didRequestListenEventAccess"

    private let onEvent: @MainActor (KeyEvent) -> Void
    private var checkTimer: Timer?
    private var running: RunningTap?

    init(onEvent: @escaping @MainActor (KeyEvent) -> Void) {
        self.onEvent = onEvent
    }

    /// `true` while the tap is running, or when the system reports the
    /// Input Monitoring permission as granted.
    var hasPermission: Bool {
        running != nil || CGPreflightListenEventAccess()
    }

    /// Starts the tap, asking for Input Monitoring the first time the app
    /// ever launches without it. Then every 2 s: if there's no tap, tries
    /// to create one (so a permission granted while the app runs takes
    /// effect without a relaunch); if there is one, checks it is still
    /// alive and tears it down if not, so it gets recreated once access is
    /// granted again.
    func start() {
        guard checkTimer == nil else { return }
        requestAccessOnce()
        tick()
        checkTimer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func tick() {
        if let running {
            if !running.isHealthy {
                running.stop()
                self.running = nil
                onRunningChanged?()
            }
        } else if let tap = RunningTap.start(onEvent: onEvent) {
            running = tap
            onRunningChanged?()
        }
    }

    private func requestAccessOnce() {
        let defaults = UserDefaults.standard
        guard !CGPreflightListenEventAccess(), !defaults.bool(forKey: Self.requestedAccessKey) else { return }
        defaults.set(true, forKey: Self.requestedAccessKey)
        _ = CGRequestListenEventAccess()
    }
}

/// One live tap and the thread whose run loop services it.
@MainActor
private final class RunningTap {
    private let context: TapContext
    private let tap: CFMachPort
    private let runLoop: UncheckedSendable<CFRunLoop>
    /// Whether the system reported the permission as granted when the tap
    /// started. Only a change from granted to not granted counts as a
    /// revocation, so a stale `false` can't tear down a working tap.
    private let hadPreflight: Bool

    private init(context: TapContext, tap: CFMachPort, runLoop: CFRunLoop, hadPreflight: Bool) {
        self.context = context
        self.tap = tap
        self.runLoop = UncheckedSendable(runLoop)
        self.hadPreflight = hadPreflight
    }

    /// Creates the tap and runs it on its own thread, so a busy main thread
    /// never stalls the tap. `nil` if the system refused (no permission
    /// yet). Without Input Monitoring the system may still hand back a
    /// tap, but a disabled one that can't be enabled, so a tap only counts
    /// once it is enabled.
    static func start(onEvent: @escaping @MainActor (KeyEventMonitor.KeyEvent) -> Void) -> RunningTap? {
        let context = TapContext(onEvent: onEvent)
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
        ) else {
            return nil
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return nil
        }
        context.tap = tap

        // The thread keeps `context` alive until its run loop exits, which
        // only happens after the tap is invalidated on that same thread, so
        // the callback never sees a freed context.
        let runLoopBox = RunLoopHandoff()
        let threadState = UncheckedSendable((context, source))
        let thread = Thread {
            let (context, source) = threadState.value
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopBox.publish(CFRunLoopGetCurrent())
            CFRunLoopRun()
            withExtendedLifetime(context) {}
        }
        thread.name = "ThaiKeyboard.KeyEventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        let runLoop = runLoopBox.wait()
        return RunningTap(context: context, tap: tap, runLoop: runLoop, hadPreflight: CGPreflightListenEventAccess())
    }

    /// `false` once the system has disabled the tap for good or the
    /// permission has gone from granted to revoked.
    var isHealthy: Bool {
        CGEvent.tapIsEnabled(tap: tap) && !(hadPreflight && !CGPreflightListenEventAccess())
    }

    /// Invalidates the tap and ends its thread. Runs the teardown on the
    /// tap's own run loop, so it can't race a callback in progress.
    func stop() {
        let state = UncheckedSendable((tap, runLoop.value))
        CFRunLoopPerformBlock(runLoop.value, CFRunLoopMode.commonModes.rawValue) {
            let (tap, runLoop) = state.value
            CFMachPortInvalidate(tap)
            CFRunLoopStop(runLoop)
        }
        CFRunLoopWakeUp(runLoop.value)
    }
}

/// Passes the tap thread's run loop back to the thread that started it.
private final class RunLoopHandoff: @unchecked Sendable {
    private let ready = DispatchSemaphore(value: 0)
    private var runLoop: CFRunLoop?

    func publish(_ runLoop: CFRunLoop) {
        self.runLoop = runLoop
        ready.signal()
    }

    /// Blocks until `publish` has run; the thread does that immediately.
    func wait() -> CFRunLoop {
        ready.wait()
        return runLoop!
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
