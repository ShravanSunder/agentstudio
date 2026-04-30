import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DrawerCompositionGateTests {
    @Test
    func tabLevelCaptureGeometryResolvesSameTargetThatDrawerOverlayCanRender() throws {
        let sourcePaneId = UUID()
        let leftPaneId = UUID()
        let rightPaneId = UUID()
        let panelFrameInTab = CGRect(x: 100, y: 200, width: 500, height: 180)
        let paneFramesInDrawer: [UUID: CGRect] = [
            leftPaneId: CGRect(x: 16, y: 40, width: 220, height: 100),
            rightPaneId: CGRect(x: 264, y: 40, width: 220, height: 100),
        ]
        let captureGeometry = try #require(
            DrawerCaptureGeometry.make(
                panelFrameInTab: panelFrameInTab,
                paneFramesInDrawer: paneFramesInDrawer
            )
        )
        let drawerLayout = DrawerGridLayout(topRow: Layout.autoTiled([sourcePaneId, leftPaneId, rightPaneId]))
        let hoverLocationInTab = CGPoint(x: 350, y: 280)
        let hoverLocationInDrawer = captureGeometry.locationInDrawer(fromTabLocation: hoverLocationInTab)

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: hoverLocationInDrawer,
            geometry: DrawerPaneDragGeometry(
                paneFrames: paneFramesInDrawer,
                layout: drawerLayout,
                containerBounds: captureGeometry.containerBounds,
                minimizedPaneIds: [],
                excludedPaneIds: [sourcePaneId]
            )
        )
        let visuals = DrawerPaneDragCoordinator.targetVisuals(
            geometry: DrawerPaneDragGeometry(
                paneFrames: paneFramesInDrawer,
                layout: drawerLayout,
                containerBounds: captureGeometry.containerBounds,
                minimizedPaneIds: [],
                excludedPaneIds: [sourcePaneId]
            )
        )

        #expect(target == .rowSlot(row: .top, insertionIndex: 1))
        let resolvedTarget = try #require(target)
        let visual = try #require(visuals[resolvedTarget])
        let markerRect = try #require(visual.insertionMarker)
        #expect(markerRect.midX == 250)
        #expect(markerRect.minY == 40)
        #expect(markerRect.height == 100)
    }
}
