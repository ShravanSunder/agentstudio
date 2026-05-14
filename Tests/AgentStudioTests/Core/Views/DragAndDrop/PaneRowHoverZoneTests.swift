import CoreGraphics
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct PaneRowHoverZoneTests {
    private static let sideZoneFloor: CGFloat = 24

    // MARK: - Plain 1/4 + 1/2 + 1/4 split (no floor effect)

    @Test
    func leftQuarterReturnsLeftZone() {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 100)

        #expect(frame.hoverZone(forX: 0, sideZoneFloor: Self.sideZoneFloor) == .left)
        #expect(frame.hoverZone(forX: 25, sideZoneFloor: Self.sideZoneFloor) == .left)
        #expect(frame.hoverZone(forX: 49.99, sideZoneFloor: Self.sideZoneFloor) == .left)
    }

    @Test
    func centerHalfReturnsCenterZone() {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 100)

        #expect(frame.hoverZone(forX: 50, sideZoneFloor: Self.sideZoneFloor) == .center)
        #expect(frame.hoverZone(forX: 100, sideZoneFloor: Self.sideZoneFloor) == .center)
        #expect(frame.hoverZone(forX: 149.99, sideZoneFloor: Self.sideZoneFloor) == .center)
    }

    @Test
    func rightQuarterReturnsRightZone() {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 100)

        #expect(frame.hoverZone(forX: 150, sideZoneFloor: Self.sideZoneFloor) == .right)
        #expect(frame.hoverZone(forX: 175, sideZoneFloor: Self.sideZoneFloor) == .right)
        #expect(frame.hoverZone(forX: 200, sideZoneFloor: Self.sideZoneFloor) == .right)
    }

    // MARK: - Frame offset (origin not at zero)

    @Test
    func zoneMathRespectsFrameOriginOffset() {
        let frame = CGRect(x: 1000, y: 0, width: 200, height: 100)

        #expect(frame.hoverZone(forX: 1025, sideZoneFloor: Self.sideZoneFloor) == .left)
        #expect(frame.hoverZone(forX: 1100, sideZoneFloor: Self.sideZoneFloor) == .center)
        #expect(frame.hoverZone(forX: 1175, sideZoneFloor: Self.sideZoneFloor) == .right)
    }

    // MARK: - Floor enforcement on narrow panes

    @Test
    func sideZoneFloorEnsuresHittableEdgesOnNarrowPane() {
        // 60 wide pane: 1/4 = 15. Floor of 24 should expand the side
        // zones so they are at least 24 wide each, leaving the center
        // zone with whatever width remains.
        let frame = CGRect(x: 0, y: 0, width: 60, height: 100)

        #expect(frame.hoverZone(forX: 0, sideZoneFloor: Self.sideZoneFloor) == .left)
        #expect(frame.hoverZone(forX: 23.99, sideZoneFloor: Self.sideZoneFloor) == .left)
        #expect(frame.hoverZone(forX: 24, sideZoneFloor: Self.sideZoneFloor) == .center)
        #expect(frame.hoverZone(forX: 35.99, sideZoneFloor: Self.sideZoneFloor) == .center)
        #expect(frame.hoverZone(forX: 36, sideZoneFloor: Self.sideZoneFloor) == .right)
        #expect(frame.hoverZone(forX: 60, sideZoneFloor: Self.sideZoneFloor) == .right)
    }

    @Test
    func sideZoneFloorCollapsesCenterWhenPaneIsTooNarrowForAllThreeZones() {
        // 40 wide pane: floor 24 each side → 48 total > 40. Collapse
        // by keeping each side zone at half the pane width; no center.
        let frame = CGRect(x: 0, y: 0, width: 40, height: 100)

        #expect(frame.hoverZone(forX: 0, sideZoneFloor: Self.sideZoneFloor) == .left)
        #expect(frame.hoverZone(forX: 19.99, sideZoneFloor: Self.sideZoneFloor) == .left)
        #expect(frame.hoverZone(forX: 20, sideZoneFloor: Self.sideZoneFloor) == .right)
        #expect(frame.hoverZone(forX: 40, sideZoneFloor: Self.sideZoneFloor) == .right)
    }
}
