import CoreText
import XCTest
@testable import ThaiKeyboardCore

final class FontResolverTests: XCTestCase {
    func test_resolverUsesPreferredFamilyWhenItHasThai() {
        let f = FontResolver(preferredFamily: "Thonburi").font(for: "ก", size: 20)
        XCTAssertEqual(CTFontCopyFamilyName(f) as String, "Thonburi")
    }

    func test_resolverFallsBackForMissingFont() {
        let f = FontResolver(preferredFamily: "No Such Font 123").font(for: "ก", size: 20)
        XCTAssertEqual(
            CTFontCopyFamilyName(f) as String,
            CTFontCopyFamilyName(FontResolver.systemThaiFont(size: 20)) as String
        )
    }

    func test_resolverFallsBackForFontWithoutThai() {
        let f = FontResolver(preferredFamily: "Courier").font(for: "\u{0E31}", size: 20)
        XCTAssertNotEqual(CTFontCopyFamilyName(f) as String, "Courier")
    }

    func test_thaiCapableFamiliesIncludeThonburiExcludeCourier() {
        let families = FontResolver.thaiCapableFamilies()
        XCTAssertTrue(families.contains("Thonburi"))
        XCTAssertFalse(families.contains("Courier"))
    }
}
