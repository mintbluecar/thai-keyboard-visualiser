import XCTest
import Carbon.HIToolbox
@testable import ThaiKeyboardCore

final class SystemLayoutTests: XCTestCase {
    func test_isThai() {
        XCTAssertTrue(SystemLayout.isThai(languages: ["th"]))
        XCTAssertTrue(SystemLayout.isThai(languages: ["th-TH"]))
        XCTAssertFalse(SystemLayout.isThai(languages: ["en", "zh-Hans"]))
    }

    func test_realThaiLayoutMatchesUsersMac() throws {
        let t = try XCTUnwrap(SystemLayout.translator(forSourceID: "com.apple.keylayout.Thai"), "Thai layout not installed")
        XCTAssertEqual(t.characters(keyCode: UInt16(kVK_ANSI_Q), state: .plain), "ๆ")
        XCTAssertEqual(t.characters(keyCode: UInt16(kVK_ANSI_Q), state: .shift), "๐")
        XCTAssertEqual(t.characters(keyCode: UInt16(kVK_ANSI_Q), state: .caps), "q")
        XCTAssertEqual(t.characters(keyCode: UInt16(kVK_ANSI_Y), state: .plain), "\u{0E31}")
    }
}
