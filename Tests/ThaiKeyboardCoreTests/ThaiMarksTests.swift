import XCTest
@testable import ThaiKeyboardCore

final class ThaiMarksTests: XCTestCase {
    func test_combiningMarksDetected() {
        for m in ["\u{0E31}", "\u{0E34}", "\u{0E35}", "\u{0E36}", "\u{0E37}", "\u{0E38}", "\u{0E39}", "\u{0E3A}",
                  "\u{0E47}", "\u{0E48}", "\u{0E49}", "\u{0E4A}", "\u{0E4B}", "\u{0E4C}", "\u{0E4D}", "\u{0E4E}"] {
            XCTAssertTrue(ThaiMarks.isCombiningMark(m), m)
        }
    }
    func test_saraAmIsTreatedAsMark() { XCTAssertTrue(ThaiMarks.isCombiningMark("\u{0E33}")) }  // ำ needs a base too
    func test_consonantsAndLatinAreNotMarks() {
        for s in ["ก", "ๆ", "ไ", "q", "", "%"] { XCTAssertFalse(ThaiMarks.isCombiningMark(s), s) }
    }
}
