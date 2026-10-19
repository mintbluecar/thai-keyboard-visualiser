import XCTest
import Carbon.HIToolbox
@testable import ThaiKeyboardCore

final class KeyGeometryTests: XCTestCase {
    func test_has47CharacterKeys() {
        XCTAssertEqual(MacBookANSI.characterKeyCodes.count, 47)
    }

    func test_characterKeyCodesAreUnique() {
        XCTAssertEqual(Set(MacBookANSI.characterKeyCodes).count, 47)
    }

    func test_everyRowIs14_5UnitsWide() {
        let rows = Dictionary(grouping: MacBookANSI.keys) { Int($0.rect.minY) }
        for (_, keys) in rows {
            XCTAssertEqual(keys.map(\.rect.maxX).max()!, 14.5, accuracy: 0.001)
        }
    }

    func test_noKeysOverlap() {
        let keys = MacBookANSI.keys
        for i in 0..<keys.count {
            for j in (i + 1)..<keys.count {
                let intersection = keys[i].rect.intersection(keys[j].rect)
                let area = intersection.isNull ? 0 : intersection.width * intersection.height
                XCTAssertEqual(
                    area, 0, accuracy: 0.0001,
                    "keys \(i) and \(j) overlap: \(keys[i].rect) vs \(keys[j].rect)"
                )
            }
        }
    }

    func test_unitSizeIs14_5by5() {
        XCTAssertEqual(MacBookANSI.unitSize, CGSize(width: 14.5, height: 5))
    }

    func test_bothShiftKeysPresent() {
        XCTAssertNotNil(MacBookANSI.keys.first { $0.keyCode == UInt16(kVK_RightShift) })
    }
}
