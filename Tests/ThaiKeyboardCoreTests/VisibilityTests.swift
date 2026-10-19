import XCTest
@testable import ThaiKeyboardCore

final class VisibilityTests: XCTestCase {
    func test_hiddenWhenNotThai() {
        XCTAssertFalse(Visibility(isThai: false).isVisible(hiddenForCaps: false))
    }

    func test_userHideLastsUntilSourceChanges() {
        var v = Visibility(isThai: true)
        v.userHide()
        XCTAssertFalse(v.isVisible(hiddenForCaps: false))
        v.inputSourceChanged(isThai: false)
        v.inputSourceChanged(isThai: true)
        XCTAssertTrue(v.isVisible(hiddenForCaps: false))
    }

    func test_switchingBetweenTwoThaiSourcesAlsoClearsHide() {
        var v = Visibility(isThai: true)
        v.userHide()
        v.inputSourceChanged(isThai: true)
        XCTAssertTrue(v.isVisible(hiddenForCaps: false))
    }

    func test_userShowOverridesHide() {
        var v = Visibility(isThai: true)
        v.userHide()
        v.userShow()
        XCTAssertTrue(v.isVisible(hiddenForCaps: false))
    }

    func test_capsHidesButUserHideStillWinsAfterCapsOff() {
        var v = Visibility(isThai: true)
        XCTAssertFalse(v.isVisible(hiddenForCaps: true))
        v.userHide()
        XCTAssertFalse(v.isVisible(hiddenForCaps: false))
    }

    func test_newLaunchInThaiIsVisible() {
        XCTAssertTrue(Visibility(isThai: true).isVisible(hiddenForCaps: false))
    }

    func test_userShowShowsEvenWhenNotThai() {
        var v = Visibility(isThai: false)
        v.userShow()
        XCTAssertTrue(v.isVisible(hiddenForCaps: false))
    }

    func test_userShowOverridesCapsHide() {
        var v = Visibility(isThai: true)
        v.userShow()
        XCTAssertTrue(v.isVisible(hiddenForCaps: true))
    }

    func test_sourceChangeEndsUserShow() {
        var v = Visibility(isThai: false)
        v.userShow()
        v.inputSourceChanged(isThai: false)
        XCTAssertFalse(v.isVisible(hiddenForCaps: false))
    }

    func test_userHideEndsUserShow() {
        var v = Visibility(isThai: false)
        v.userShow()
        v.userHide()
        XCTAssertFalse(v.isVisible(hiddenForCaps: false))
    }
}
