import XCTest
@testable import ThaiKeyboardCore

private struct Fake: KeyTranslator {
    let map: [UInt16: [KeyState: String]]
    func characters(keyCode: UInt16, state: KeyState) -> String {
        map[keyCode]?[state] ?? ""
    }
}

final class KeyLabelsTests: XCTestCase {
    func test_labelsComeFromTranslator() {
        let t = LabelTable(
            translator: Fake(map: [12: [.plain: "ๆ", .shift: "๐", .caps: "q", .capsShift: "Q"]]),
            keyCodes: [12]
        )
        XCTAssertEqual(t.label(12, .plain), "ๆ")
        XCTAssertEqual(t.label(12, .shift), "๐")
        XCTAssertEqual(t.label(12, .caps), "q")
    }

    func test_controlCharactersBecomeBlank() {
        let t = LabelTable(
            translator: Fake(map: [12: [.plain: "\u{10}", .shift: "", .caps: "", .capsShift: ""]]),
            keyCodes: [12]
        )
        XCTAssertEqual(t.label(12, .plain), "")
    }

    func test_capsChangesOutputFalseWhenCapsMatchesPlain() {
        let t = LabelTable(
            translator: Fake(map: [
                12: [.plain: "ๆ", .shift: "๐", .caps: "ๆ", .capsShift: "๐"],
                13: [.plain: "ไ", .shift: "ฺ", .caps: "ไ", .capsShift: "ฺ"],
            ]),
            keyCodes: [12, 13]
        )
        XCTAssertFalse(t.capsChangesOutput)
    }

    func test_displayModePlainAndShift() {
        XCTAssertEqual(displayMode(shift: false, capsLock: false, capsChangesOutput: true, showCapsOutput: false), .thai(.plain))
        XCTAssertEqual(displayMode(shift: true, capsLock: false, capsChangesOutput: true, showCapsOutput: false), .thai(.shift))
    }

    func test_capsHidesByDefaultWhenItChangesOutput() {
        XCTAssertEqual(displayMode(shift: false, capsLock: true, capsChangesOutput: true, showCapsOutput: false), .hiddenForCaps)
    }

    func test_capsShowsOutputWhenToggleOn() {
        XCTAssertEqual(displayMode(shift: true, capsLock: true, capsChangesOutput: true, showCapsOutput: true), .capsOutput(.capsShift))
    }

    func test_capsIgnoredWhenItChangesNothing() {
        XCTAssertEqual(displayMode(shift: false, capsLock: true, capsChangesOutput: false, showCapsOutput: false), .thai(.plain))
    }
}
