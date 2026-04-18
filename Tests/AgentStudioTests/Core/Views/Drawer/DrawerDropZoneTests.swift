import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DrawerDropZoneTests {
    @Test
    func calculate_prefersTopEdge() {
        let zone = DrawerDropZone.calculate(
            at: CGPoint(x: 50, y: 95),
            in: CGSize(width: 100, height: 100)
        )

        #expect(zone == .top)
        #expect(zone.newDirection == .up)
    }

    @Test
    func calculate_prefersBottomEdge() {
        let zone = DrawerDropZone.calculate(
            at: CGPoint(x: 50, y: 5),
            in: CGSize(width: 100, height: 100)
        )

        #expect(zone == .bottom)
        #expect(zone.newDirection == .down)
    }

    @Test
    func dragCoordinator_resolvesContainedPaneAndZone() {
        let paneId = UUID()
        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: CGPoint(x: 50, y: 90),
            paneFrames: [paneId: CGRect(x: 0, y: 0, width: 100, height: 100)]
        )

        #expect(target == DrawerPaneDropTarget(paneId: paneId, zone: .top))
    }

    @Test
    func dragCoordinator_resolveLatchedTarget_keepsCurrentTargetWhenLocationFallsOutside() {
        let paneId = UUID()
        let currentTarget = DrawerPaneDropTarget(paneId: paneId, zone: .bottom)

        let target = DrawerPaneDragCoordinator.resolveLatchedTarget(
            location: CGPoint(x: 200, y: 200),
            paneFrames: [paneId: CGRect(x: 0, y: 0, width: 100, height: 100)],
            currentTarget: currentTarget,
            shouldAcceptDrop: { _, _ in true }
        )

        #expect(target == currentTarget)
    }
}
