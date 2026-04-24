import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("DrawerDragOwnershipPolicyTests")
struct DrawerDragOwnershipPolicyTests {
    @Test
    func mainSplitDragEnabled_activeManagementWithoutExpandedDrawer_isTrue() {
        let isEnabled = DrawerDragOwnershipPolicy.mainSplitDragEnabled(
            managementLayerActive: true,
            expandedDrawerParentPaneId: nil
        )

        #expect(isEnabled)
    }

    @Test
    func mainSplitDragEnabled_expandedDrawerDisablesMainCapture() {
        let isEnabled = DrawerDragOwnershipPolicy.mainSplitDragEnabled(
            managementLayerActive: true,
            expandedDrawerParentPaneId: UUID()
        )

        #expect(!isEnabled)
    }

    @Test
    func drawerCaptureEnabled_requiresManagementExpandedDrawerAndPanelFrame() {
        let expandedDrawerParentPaneId = UUID()
        let panelFrame = CGRect(x: 10, y: 20, width: 300, height: 180)

        #expect(
            DrawerDragOwnershipPolicy.drawerCaptureEnabled(
                managementLayerActive: true,
                expandedDrawerParentPaneId: expandedDrawerParentPaneId,
                drawerPanelFrameInTab: panelFrame
            )
        )
        #expect(
            !DrawerDragOwnershipPolicy.drawerCaptureEnabled(
                managementLayerActive: false,
                expandedDrawerParentPaneId: expandedDrawerParentPaneId,
                drawerPanelFrameInTab: panelFrame
            )
        )
        #expect(
            !DrawerDragOwnershipPolicy.drawerCaptureEnabled(
                managementLayerActive: true,
                expandedDrawerParentPaneId: nil,
                drawerPanelFrameInTab: panelFrame
            )
        )
        #expect(
            !DrawerDragOwnershipPolicy.drawerCaptureEnabled(
                managementLayerActive: true,
                expandedDrawerParentPaneId: expandedDrawerParentPaneId,
                drawerPanelFrameInTab: .zero
            )
        )
    }
}
