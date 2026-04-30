import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DrawerCaptureGeometryTests {
    @Test
    func readiness_waitsForPanelFrameButCanMountBeforePaneFramesArrive() throws {
        let paneId = UUID()

        #expect(
            DrawerCaptureGeometry.make(
                panelFrameInTab: .zero,
                paneFramesInDrawer: [paneId: CGRect(x: 0, y: 0, width: 100, height: 80)]
            ) == nil
        )

        let geometry = try #require(
            DrawerCaptureGeometry.make(
                panelFrameInTab: CGRect(x: 20, y: 30, width: 400, height: 160),
                paneFramesInDrawer: [:]
            )
        )

        #expect(geometry.containerBounds == CGRect(x: 0, y: 0, width: 400, height: 160))
        #expect(geometry.paneFramesInDrawer.isEmpty)
    }

    @Test
    func readyGeometryUsesPanelOnlyBounds() throws {
        let leftPaneId = UUID()
        let rightPaneId = UUID()

        let geometry = try #require(
            DrawerCaptureGeometry.make(
                panelFrameInTab: CGRect(x: 100, y: 200, width: 500, height: 180),
                paneFramesInDrawer: [
                    leftPaneId: CGRect(x: 16, y: 40, width: 220, height: 100),
                    rightPaneId: CGRect(x: 264, y: 40, width: 220, height: 100),
                ]
            )
        )

        #expect(geometry.containerBounds == CGRect(x: 0, y: 0, width: 500, height: 180))
        #expect(geometry.locationInDrawer(fromTabLocation: CGPoint(x: 350, y: 280)) == CGPoint(x: 250, y: 80))
    }

    @Test
    func readyGeometryAcceptsPaneFramesEvenIfTheyOverflowPanelBounds() throws {
        let paneId = UUID()
        let geometry = try #require(
            DrawerCaptureGeometry.make(
                panelFrameInTab: CGRect(x: 100, y: 200, width: 500, height: 180),
                paneFramesInDrawer: [
                    paneId: CGRect(x: 16, y: 40, width: 220, height: 200)
                ]
            )
        )

        #expect(geometry.containerBounds == CGRect(x: 0, y: 0, width: 500, height: 180))
        #expect(geometry.paneFramesInDrawer[paneId]?.height == 200)
    }
}
