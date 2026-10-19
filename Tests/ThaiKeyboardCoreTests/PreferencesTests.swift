import XCTest
@testable import ThaiKeyboardCore

final class PreferencesTests: XCTestCase {
    private var suiteName = ""
    private var d: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "PreferencesTests." + UUID().uuidString
        d = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        d.removePersistentDomain(forName: suiteName)
        d = nil
        super.tearDown()
    }

    func test_defaults() {
        let p = Preferences(defaults: d)
        XCTAssertNil(p.fontFamily)
        XCTAssertEqual(p.opacity, 0.9)
        XCTAssertNil(p.frame)
        XCTAssertFalse(p.showCapsOutput)
        XCTAssertTrue(p.startAtLogin)
        XCTAssertEqual(p.hotkeys, Hotkeys.defaults)
    }

    func test_roundTrip() {
        let p = Preferences(defaults: d)
        p.fontFamily = "Sukhumvit Set"
        p.opacity = 0.5
        p.frame = CGRect(x: 10, y: 20, width: 300, height: 150)
        p.showCapsOutput = true
        p.startAtLogin = false
        var hotkeys = Hotkeys.defaults
        hotkeys[.bigger] = HotkeyBinding(keyCode: 99, carbonModifiers: 42)
        p.hotkeys = hotkeys

        let p2 = Preferences(defaults: d)
        XCTAssertEqual(p2.fontFamily, "Sukhumvit Set")
        XCTAssertEqual(p2.opacity, 0.5)
        XCTAssertEqual(p2.frame, CGRect(x: 10, y: 20, width: 300, height: 150))
        XCTAssertTrue(p2.showCapsOutput)
        XCTAssertFalse(p2.startAtLogin)
        XCTAssertEqual(p2.hotkeys, hotkeys)
    }

    func test_opacityClamped() {
        let p = Preferences(defaults: d)
        p.opacity = 0.0
        XCTAssertEqual(p.opacity, 0.2)
        p.opacity = 3
        XCTAssertEqual(p.opacity, 1.0)
    }

    func test_defaultHotkeysCoverEveryActionOnce() {
        XCTAssertEqual(Set(Hotkeys.defaults.keys), Set(HotkeyAction.allCases))
    }
}
