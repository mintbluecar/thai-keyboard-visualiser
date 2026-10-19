import XCTest
@testable import ThaiKeyboardCore

final class PlacementTests: XCTestCase {
    let vis = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func test_defaultFrameIs60PercentBottomCentre() {
        let f = Placement.defaultFrame(visible: vis, aspect: 3)
        XCTAssertEqual(f.width, 600, accuracy: 0.5)
        XCTAssertEqual(f.midX, 500, accuracy: 0.5)
        XCTAssertEqual(f.minY, 12, accuracy: 0.5)
    }

    func test_snapCorners() {
        let frame = CGRect(x: 200, y: 150, width: 400, height: 300)

        for target in SnapTarget.allCases {
            let snapped = Placement.snapped(frame, to: target, in: vis)

            // Size is always preserved by snapping.
            XCTAssertEqual(snapped.width, frame.width, accuracy: 0.001, "\(target)")
            XCTAssertEqual(snapped.height, frame.height, accuracy: 0.001, "\(target)")

            switch target {
            case .top:
                XCTAssertEqual(snapped.midX, vis.midX, accuracy: 0.5, "\(target)")
                XCTAssertEqual(snapped.maxY, vis.maxY - Placement.margin, accuracy: 0.5, "\(target)")
            case .bottom:
                XCTAssertEqual(snapped.midX, vis.midX, accuracy: 0.5, "\(target)")
                XCTAssertEqual(snapped.minY, vis.minY + Placement.margin, accuracy: 0.5, "\(target)")
            case .left:
                XCTAssertEqual(snapped.midY, vis.midY, accuracy: 0.5, "\(target)")
                XCTAssertEqual(snapped.minX, vis.minX + Placement.margin, accuracy: 0.5, "\(target)")
            case .right:
                XCTAssertEqual(snapped.midY, vis.midY, accuracy: 0.5, "\(target)")
                XCTAssertEqual(snapped.maxX, vis.maxX - Placement.margin, accuracy: 0.5, "\(target)")
            case .topLeft:
                XCTAssertEqual(snapped.minX, vis.minX + Placement.margin, accuracy: 0.5, "\(target)")
                XCTAssertEqual(snapped.maxY, vis.maxY - Placement.margin, accuracy: 0.5, "\(target)")
            case .topRight:
                XCTAssertEqual(snapped.maxX, vis.maxX - Placement.margin, accuracy: 0.5, "\(target)")
                XCTAssertEqual(snapped.maxY, vis.maxY - Placement.margin, accuracy: 0.5, "\(target)")
            case .bottomLeft:
                XCTAssertEqual(snapped.minX, vis.minX + Placement.margin, accuracy: 0.5, "\(target)")
                XCTAssertEqual(snapped.minY, vis.minY + Placement.margin, accuracy: 0.5, "\(target)")
            case .bottomRight:
                XCTAssertEqual(snapped.maxX, vis.maxX - Placement.margin, accuracy: 0.5, "\(target)")
                XCTAssertEqual(snapped.minY, vis.minY + Placement.margin, accuracy: 0.5, "\(target)")
            }
        }
    }

    func test_resizeKeepsAspectAndCentre() {
        let frame = CGRect(x: 300, y: 250, width: 500, height: 250)
        let aspect: CGFloat = 2
        let resized = Placement.resized(frame, step: 1, aspect: aspect, in: vis)

        XCTAssertEqual(resized.width, frame.width * 1.1, accuracy: 0.001)
        XCTAssertEqual(resized.height, resized.width / aspect, accuracy: 0.001)
        XCTAssertEqual(resized.midX, frame.midX, accuracy: 0.001)
        XCTAssertEqual(resized.midY, frame.midY, accuracy: 0.001)
    }

    func test_resizeRoundTrips() {
        let frame = CGRect(x: 300, y: 250, width: 500, height: 250)
        let aspect: CGFloat = 2
        let grown = Placement.resized(frame, step: 1, aspect: aspect, in: vis)
        let backToOriginal = Placement.resized(grown, step: -1, aspect: aspect, in: vis)

        XCTAssertEqual(backToOriginal.width, frame.width, accuracy: 0.001)
    }

    func test_resizeClampsToMinAndScreen() {
        let aspect: CGFloat = 2
        var frame = CGRect(x: 400, y: 350, width: 500, height: 250)

        for _ in 0..<200 {
            frame = Placement.resized(frame, step: -1, aspect: aspect, in: vis)
        }
        XCTAssertEqual(frame.width, 360, accuracy: 0.5)

        frame = CGRect(x: 400, y: 350, width: 500, height: 250)
        for _ in 0..<200 {
            frame = Placement.resized(frame, step: 1, aspect: aspect, in: vis)
        }
        XCTAssertEqual(frame.width, vis.width - 2 * Placement.margin, accuracy: 0.5)
    }

    func test_clampMovesOffscreenFrameIntoVisibleArea() {
        let f = Placement.clamped(CGRect(x: 2500, y: -400, width: 600, height: 200), in: vis)
        XCTAssertTrue(vis.contains(f))
    }

    func test_clampShrinksOversizedFrame() {
        let f = Placement.clamped(CGRect(x: 0, y: 0, width: 2000, height: 1600), in: vis)
        XCTAssertTrue(vis.contains(f))
        XCTAssertEqual(f.width / f.height, 2000.0 / 1600.0, accuracy: 0.001)
    }

    func test_clampLeavesFrameAlreadyInsideUnchanged() {
        let inside = CGRect(x: 100, y: 100, width: 400, height: 300)
        let f = Placement.clamped(inside, in: vis)
        XCTAssertEqual(f, inside)
    }

    func test_resizedToWidthKeepsCentreAndAspect() {
        let frame = CGRect(x: 300, y: 250, width: 500, height: 250)
        let aspect: CGFloat = 2
        let resized = Placement.resized(frame, toWidth: 700, aspect: aspect, in: vis)

        XCTAssertEqual(resized.width, 700, accuracy: 0.001)
        XCTAssertEqual(resized.height, resized.width / aspect, accuracy: 0.001)
        XCTAssertEqual(resized.midX, frame.midX, accuracy: 0.001)
        XCTAssertEqual(resized.midY, frame.midY, accuracy: 0.001)
    }

    func test_resizedToWidthClampsToMinAndScreen() {
        let frame = CGRect(x: 400, y: 350, width: 500, height: 250)
        let aspect: CGFloat = 2

        let tooNarrow = Placement.resized(frame, toWidth: 10, aspect: aspect, in: vis)
        XCTAssertEqual(tooNarrow.width, Placement.minWidth, accuracy: 0.5)

        let tooWide = Placement.resized(frame, toWidth: 5000, aspect: aspect, in: vis)
        XCTAssertEqual(tooWide.width, vis.width - 2 * Placement.margin, accuracy: 0.5)
    }

    func test_resizedToWidthStaysInsideVisible() {
        let frame = CGRect(x: 950, y: 750, width: 100, height: 50)
        let resized = Placement.resized(frame, toWidth: 900, aspect: 2, in: vis)
        XCTAssertTrue(vis.contains(resized))
    }
}
