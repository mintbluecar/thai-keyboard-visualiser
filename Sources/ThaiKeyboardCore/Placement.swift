import CoreGraphics

/// An edge or corner of the visible screen area the panel can snap to.
public enum SnapTarget: CaseIterable, Sendable {
    case top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight
}

/// Default frame, snapping, resizing and clamping maths for the keyboard
/// panel window. All coordinates are AppKit's: origin bottom-left, and
/// `visible` is always `NSScreen.visibleFrame`.
public enum Placement {
    /// Gap kept between the panel and the edge of the visible screen area
    /// when snapping, and the minimum gap enforced on resize.
    public static let margin: CGFloat = 12

    /// The narrowest the panel is ever allowed to shrink to.
    public static let minWidth: CGFloat = 360

    /// Factor applied to the width on each resize step.
    private static let resizeFactor: CGFloat = 1.1

    /// Bottom-centre of `visible`, 60% of its width, with `aspect`
    /// (width / height) determining the height.
    public static func defaultFrame(visible: CGRect, aspect: CGFloat) -> CGRect {
        let width = visible.width * 0.6
        let height = width / aspect
        return CGRect(
            x: visible.midX - width / 2,
            y: visible.minY + margin,
            width: width,
            height: height
        )
    }

    /// `frame` moved to `target`, keeping its size. An edge target centres
    /// the frame along the other axis; a corner target pins both axes.
    public static func snapped(_ frame: CGRect, to target: SnapTarget, in visible: CGRect) -> CGRect {
        var origin = frame.origin

        switch target {
        case .top:
            origin.x = visible.midX - frame.width / 2
            origin.y = visible.maxY - margin - frame.height
        case .bottom:
            origin.x = visible.midX - frame.width / 2
            origin.y = visible.minY + margin
        case .left:
            origin.x = visible.minX + margin
            origin.y = visible.midY - frame.height / 2
        case .right:
            origin.x = visible.maxX - margin - frame.width
            origin.y = visible.midY - frame.height / 2
        case .topLeft:
            origin.x = visible.minX + margin
            origin.y = visible.maxY - margin - frame.height
        case .topRight:
            origin.x = visible.maxX - margin - frame.width
            origin.y = visible.maxY - margin - frame.height
        case .bottomLeft:
            origin.x = visible.minX + margin
            origin.y = visible.minY + margin
        case .bottomRight:
            origin.x = visible.maxX - margin - frame.width
            origin.y = visible.minY + margin
        }

        return CGRect(origin: origin, size: frame.size)
    }

    /// `frame` resized by `step` increments of ±10% width (dividing by
    /// 1.1 rather than multiplying by 0.9, so growing then shrinking by
    /// the same step count round-trips), keeping its centre fixed and its
    /// height derived from `aspect`. Width is clamped to
    /// `[minWidth, visible.width - 2*margin]`, then the whole frame is
    /// clamped into `visible`.
    public static func resized(_ frame: CGRect, step: Int, aspect: CGFloat, in visible: CGRect) -> CGRect {
        let centre = CGPoint(x: frame.midX, y: frame.midY)

        var width = frame.width
        if step > 0 {
            for _ in 0..<step { width *= resizeFactor }
        } else if step < 0 {
            for _ in 0..<(-step) { width /= resizeFactor }
        }

        let maxWidth = max(minWidth, visible.width - 2 * margin)
        width = min(max(width, minWidth), maxWidth)
        let height = width / aspect

        let resized = CGRect(
            x: centre.x - width / 2,
            y: centre.y - height / 2,
            width: width,
            height: height
        )
        return clamped(resized, in: visible)
    }

    /// `frame` moved (and, if necessary, scaled down uniformly keeping its
    /// own aspect ratio) so it lies fully inside `visible`. A frame already
    /// inside is returned unchanged.
    public static func clamped(_ frame: CGRect, in visible: CGRect) -> CGRect {
        var result = frame

        if result.width > visible.width || result.height > visible.height {
            let scale = min(visible.width / result.width, visible.height / result.height)
            let width = result.width * scale
            let height = result.height * scale
            result = CGRect(
                x: result.midX - width / 2,
                y: result.midY - height / 2,
                width: width,
                height: height
            )
        }

        var origin = result.origin
        if origin.x < visible.minX { origin.x = visible.minX }
        if origin.x + result.width > visible.maxX { origin.x = visible.maxX - result.width }
        if origin.y < visible.minY { origin.y = visible.minY }
        if origin.y + result.height > visible.maxY { origin.y = visible.maxY - result.height }

        return CGRect(origin: origin, size: result.size)
    }
}
