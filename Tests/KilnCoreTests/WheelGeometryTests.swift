import Testing
@testable import KilnCore

@Suite struct WheelGeometryTests {
    let g = WheelGeometry.standard
    @Test func topIsWedgeZero() { #expect(g.zone(dx: 0, dy: -80, innerCount: 4, outerCount: 0) == .inner(0)) }
    @Test func rightIsWedgeOneOfFour() { #expect(g.zone(dx: 80, dy: 0, innerCount: 4, outerCount: 0) == .inner(1)) }
    @Test func bottomAndLeft() {
        #expect(g.zone(dx: 0, dy: 80, innerCount: 4, outerCount: 0) == .inner(2))
        #expect(g.zone(dx: -80, dy: 0, innerCount: 4, outerCount: 0) == .inner(3))
    }
    @Test func justLeftOfTopWrapsToWedgeZero() { #expect(g.zone(dx: -5, dy: -80, innerCount: 6, outerCount: 0) == .inner(0)) }
    @Test func singleWedgeCoversEverything() {
        for (x, y) in [(0.0, -80.0), (80, 0), (0, 80), (-80, 0)] { #expect(g.zone(dx: x, dy: y, innerCount: 1, outerCount: 0) == .inner(0)) }
    }
    @Test func hubInsideAndOutsideBeyond() {
        #expect(g.zone(dx: 10, dy: 10, innerCount: 4, outerCount: 4) == .hub)
        #expect(g.zone(dx: 0, dy: -200, innerCount: 4, outerCount: 4) == .outside)
    }
    @Test func outerRingNeedsItems() {
        #expect(g.zone(dx: 0, dy: -160, innerCount: 4, outerCount: 0) == .outside)
        #expect(g.zone(dx: 0, dy: -160, innerCount: 4, outerCount: 8) == .outer(0))
    }
    @Test func ringGapSplitsAtTheMiddle() {
        #expect(g.zone(dx: 0, dy: -116, innerCount: 4, outerCount: 4) == .inner(0))
        #expect(g.zone(dx: 0, dy: -119, innerCount: 4, outerCount: 4) == .outer(0))
    }
    @Test func wedgeAnglesTileTheCircle() {
        for n in 1...10 { #expect(abs(WheelGeometry.startAngle(n, of: n) - WheelGeometry.startAngle(0, of: n) - 360) < 1e-9) }
    }
}
