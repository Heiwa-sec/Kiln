import AppKit

extension NSScreen {
    /// The screen holding a point, or the main screen.
    static func at(_ p: NSPoint) -> NSScreen? { screens.first { $0.frame.contains(p) } ?? main }

    /// Nudges a window origin so a window of `size` stays fully inside the visible area of the screen holding `p`.
    static func keepOnScreen(_ origin: NSPoint, size: CGSize, near p: NSPoint, margin: CGFloat = 4) -> NSPoint {
        guard let f = at(p)?.visibleFrame else { return origin }
        return NSPoint(x: min(max(origin.x, f.minX + margin), f.maxX - size.width - margin),
                       y: min(max(origin.y, f.minY + margin), f.maxY - size.height - margin))
    }
}
