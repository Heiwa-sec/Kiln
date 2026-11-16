import Foundation

/// Pure wheel math in view coordinates (y grows downward). Angles are degrees clockwise from the top.
/// Wedge 0 is centred on the top. Kept free of UI so it can be unit-tested.
public struct WheelGeometry: Sendable, Equatable {
    public var hub, innerFrom, innerTo, outerFrom, outerTo: Double
    public static let standard = WheelGeometry(hub: 44, innerFrom: 50, innerTo: 114, outerFrom: 120, outerTo: 184)

    public enum Zone: Equatable, Sendable { case hub, inner(Int), outer(Int), outside }

    public static func span(_ count: Int) -> Double { 360 / Double(max(count, 1)) }
    public static func midAngle(_ i: Int, of n: Int) -> Double { Double(i) * span(n) }
    public static func startAngle(_ i: Int, of n: Int) -> Double { midAngle(i, of: n) - span(n) / 2 }

    public static func angle(dx: Double, dy: Double) -> Double {
        let a = atan2(dx, -dy) * 180 / .pi
        return a < 0 ? a + 360 : a
    }

    public static func wedge(angle: Double, count: Int) -> Int {
        let s = span(count)
        return min(Int(((angle + s / 2).truncatingRemainder(dividingBy: 360)) / s), count - 1)
    }

    /// The gap between the rings belongs to whichever ring is nearer.
    public func zone(dx: Double, dy: Double, innerCount: Int, outerCount: Int) -> Zone {
        let r = hypot(dx, dy)
        if r < innerFrom { return .hub }
        let a = Self.angle(dx: dx, dy: dy)
        if r < (innerTo + outerFrom) / 2 { return innerCount > 0 ? .inner(Self.wedge(angle: a, count: innerCount)) : .outside }
        if r <= outerTo { return outerCount > 0 ? .outer(Self.wedge(angle: a, count: outerCount)) : .outside }
        return .outside
    }
}
