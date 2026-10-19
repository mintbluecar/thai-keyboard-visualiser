import XCTest
@testable import ThaiKeyboardCore

final class PressedKeysTests: XCTestCase {
    func test_downUpTracksKeys() {
        var p = PressedKeys()
        p.keyDown(12)
        XCTAssertEqual(p.keys, [12])
        p.keyUp(12)
        XCTAssertEqual(p.keys, [])
    }

    func test_flagsFromEventNotCounting() {
        var p = PressedKeys()
        p.flagsChanged(shift: true, capsLock: false)
        p.flagsChanged(shift: true, capsLock: false)
        XCTAssertTrue(p.shift)
    }

    func test_resetClearsPressedKeys() {
        var p = PressedKeys()
        p.keyDown(12)
        p.flagsChanged(shift: true, capsLock: true)
        p.reset()
        XCTAssertEqual(p.keys, [])
        XCTAssertFalse(p.shift)
    }

    func test_resetKeepsCapsLockSinceItIsALatchedState() {
        var p = PressedKeys()
        p.flagsChanged(shift: false, capsLock: true)
        p.reset()
        XCTAssertTrue(p.capsLock)
    }
}
