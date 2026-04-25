import AppKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct FlatTabStripContainerDragOwnershipTests {
    private static let nonEmptyFrame = NSRect(x: 0, y: 0, width: 400, height: 300)

    @Test
    func expandedDrawer_enablesDrawerCaptureRegistration() {
        let drawerCapture = DrawerSplitContainerDropCaptureView(frame: Self.nonEmptyFrame)

        let drawerEnabled = DrawerDragOwnershipPolicy.drawerCaptureEnabled(
            managementLayerActive: true,
            expandedDrawerParentPaneId: UUID(),
            drawerPanelFrameInTab: Self.nonEmptyFrame
        )

        drawerCapture.updateDropRegistration(isManagementLayerActive: drawerEnabled)

        #expect(drawerCapture.registeredDraggedTypes.contains(NSPasteboard.PasteboardType.agentStudioPaneDrop))
    }

    @Test
    func collapsedDrawer_enablesMainCaptureRegistration() {
        let mainCapture = SplitContainerDropCaptureView(frame: Self.nonEmptyFrame)

        let mainEnabled = DrawerDragOwnershipPolicy.mainSplitDragEnabled(
            managementLayerActive: true,
            expandedDrawerParentPaneId: nil
        )

        mainCapture.updateDropRegistration(isManagementLayerActive: mainEnabled)

        #expect(mainCapture.registeredDraggedTypes.contains(NSPasteboard.PasteboardType.agentStudioPaneDrop))
    }

    @Test
    func drawerEmptyFrame_blocksRegistration_evenWhenManagementLayerActive() {
        let drawerCapture = DrawerSplitContainerDropCaptureView(frame: .zero)

        drawerCapture.updateDropRegistration(isManagementLayerActive: true)

        #expect(drawerCapture.registeredDraggedTypes.isEmpty)
    }

    @Test
    func emptyFrame_registersAfterResize() {
        let drawerCapture = DrawerSplitContainerDropCaptureView(frame: .zero)

        drawerCapture.updateDropRegistration(isManagementLayerActive: true)
        #expect(drawerCapture.registeredDraggedTypes.isEmpty)

        drawerCapture.setFrameSize(NSSize(width: 400, height: 300))

        #expect(drawerCapture.registeredDraggedTypes.contains(NSPasteboard.PasteboardType.agentStudioPaneDrop))
    }

    /// Pins the load-bearing AppKit invariant: while a drawer is expanded the
    /// main capture must not be registered for `.agentStudioPaneDrop`. If both
    /// are registered, AppKit's first-matching-destination-wins-the-session
    /// rule lets the main capture intercept and silence the drawer drag.
    @Test
    func drawerExpanded_disablesMainCaptureRegistration_whileDrawerCaptureIsRegistered() {
        let mainCapture = SplitContainerDropCaptureView(frame: Self.nonEmptyFrame)
        let drawerCapture = DrawerSplitContainerDropCaptureView(frame: Self.nonEmptyFrame)
        let parentPaneId = UUID()

        let mainEnabled = DrawerDragOwnershipPolicy.mainSplitDragEnabled(
            managementLayerActive: true,
            expandedDrawerParentPaneId: parentPaneId
        )
        let drawerEnabled = DrawerDragOwnershipPolicy.drawerCaptureEnabled(
            managementLayerActive: true,
            expandedDrawerParentPaneId: parentPaneId,
            drawerPanelFrameInTab: Self.nonEmptyFrame
        )

        mainCapture.updateDropRegistration(isManagementLayerActive: mainEnabled)
        drawerCapture.updateDropRegistration(isManagementLayerActive: drawerEnabled)

        #expect(mainCapture.registeredDraggedTypes.isEmpty)
        #expect(drawerCapture.registeredDraggedTypes.contains(NSPasteboard.PasteboardType.agentStudioPaneDrop))
    }
}
