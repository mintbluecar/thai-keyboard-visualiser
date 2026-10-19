import XCTest
@testable import ThaiKeyboardCore

final class CompatibilityTests: XCTestCase {
    private func report(
        isThai: Bool = true,
        keyboardType: KeyboardType = .ansi,
        inputMonitoring: Bool = true,
        capsChangesOutput: Bool = true,
        failedHotkeys: Set<HotkeyAction> = []
    ) -> CompatibilityReport {
        CompatibilityReport(
            inputSource: InputSourceInfo(id: "com.apple.keylayout.Thai", name: "Thai", isThai: isThai),
            keyboardType: keyboardType,
            inputMonitoring: inputMonitoring,
            capsChangesOutput: capsChangesOutput,
            failedHotkeys: failedHotkeys
        )
    }

    func test_allGoodHasNoActionItems() {
        let r = report()
        XCTAssertEqual(r.lines.count, 4)
        XCTAssertTrue(r.actionItems.isEmpty)
        XCTAssertEqual(r.lines[3], "Caps Lock: types different characters in this layout")
    }

    func test_missingPermissionIsActionItem() {
        let r = report(inputMonitoring: false)
        XCTAssertEqual(r.actionItems, ["Key presses: not allowed — grant Input Monitoring in System Settings"])
    }

    func test_isoKeyboardIsActionItem() {
        let r = report(keyboardType: .iso)
        XCTAssertTrue(r.actionItems.contains("Keyboard: ISO — drawn as MacBook ANSI, may not match your keys"))
    }

    func test_reportListsFailedHotkeys() {
        let r = report(failedHotkeys: [.snapLeft])
        XCTAssertEqual(r.lines.count, 5)
        XCTAssertTrue(r.lines.last!.hasPrefix("Hotkeys in use by another app:"))
        XCTAssertTrue(r.actionItems.contains(r.lines.last!))
    }

    func test_notThaiLine() {
        let r = report(isThai: false)
        XCTAssertTrue(r.lines[0].hasSuffix("— not Thai, keyboard hidden"))
    }
}
