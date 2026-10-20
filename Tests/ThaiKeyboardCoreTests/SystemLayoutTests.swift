import XCTest
import Carbon.HIToolbox
@testable import ThaiKeyboardCore

final class SystemLayoutTests: XCTestCase {
    func test_isThai() {
        XCTAssertTrue(SystemLayout.isThai(languages: ["th"]))
        XCTAssertTrue(SystemLayout.isThai(languages: ["th-TH"]))
        XCTAssertFalse(SystemLayout.isThai(languages: ["en", "zh-Hans"]))
        XCTAssertFalse(SystemLayout.isThai(languages: []))
    }

    /// Only the first language is the one a source is intended for
    /// (TextInputSources.h); Unicode Hex Input lists "th" among hundreds
    /// with an empty first entry, and must not count as Thai.
    func test_isThaiChecksOnlyThePrimaryLanguage() {
        XCTAssertFalse(SystemLayout.isThai(languages: ["", "en", "fr", "th"]))
        XCTAssertFalse(SystemLayout.isThai(languages: ["en", "th"]))
        XCTAssertTrue(SystemLayout.isThai(languages: ["th", "en"]))
        XCTAssertFalse(SystemLayout.isThai(languages: ["thv"]))
    }

    func test_realThaiLayoutMatchesUsersMac() throws {
        let t = try XCTUnwrap(SystemLayout.translator(forSourceID: "com.apple.keylayout.Thai"), "Thai layout not installed")
        XCTAssertEqual(t.characters(keyCode: UInt16(kVK_ANSI_Q), state: .plain), "ๆ")
        XCTAssertEqual(t.characters(keyCode: UInt16(kVK_ANSI_Q), state: .shift), "๐")
        XCTAssertEqual(t.characters(keyCode: UInt16(kVK_ANSI_Q), state: .caps), "q")
        XCTAssertEqual(t.characters(keyCode: UInt16(kVK_ANSI_Y), state: .plain), "\u{0E31}")
    }

    private let thai = InputSourceInfo(id: "com.apple.keylayout.Thai", name: "Thai", isThai: true)
    private let pattachote = InputSourceInfo(id: "com.apple.keylayout.Thai-PattaChote", name: "Thai - Pattachote", isThai: true)
    private let abc = InputSourceInfo(id: "com.apple.keylayout.ABC", name: "ABC", isThai: false)

    func test_thaiSourceToSelectPrefersLastUsed() {
        XCTAssertEqual(SystemLayout.thaiSourceToSelect(lastUsed: pattachote.id, enabled: [abc, thai, pattachote]), pattachote.id)
    }

    func test_thaiSourceToSelectFallsBackToFirstThai() {
        XCTAssertEqual(SystemLayout.thaiSourceToSelect(lastUsed: nil, enabled: [abc, thai, pattachote]), thai.id)
        XCTAssertEqual(SystemLayout.thaiSourceToSelect(lastUsed: "gone", enabled: [abc, pattachote]), pattachote.id)
    }

    func test_thaiSourceToSelectIgnoresNonThaiLastUsed() {
        XCTAssertEqual(SystemLayout.thaiSourceToSelect(lastUsed: abc.id, enabled: [abc, thai]), thai.id)
    }

    func test_thaiSourceToSelectNilWithoutThai() {
        XCTAssertNil(SystemLayout.thaiSourceToSelect(lastUsed: nil, enabled: [abc]))
    }

    func test_enabledThaiSourcesIncludesUsersThaiLayout() {
        XCTAssertTrue(SystemLayout.enabledThaiSources().contains { $0.id == "com.apple.keylayout.Thai" },
                      "Thai layout not turned on")
    }
}
