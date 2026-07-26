import AppKit
import Testing

@testable import AgentStudio

/// Pin the load-bearing AppKit invariant on the policy layer:
/// while a drawer is expanded the main capture must be disabled, while
/// the drawer capture must be enabled. If both could register for
/// `.agentStudioPaneDrop` simultaneously, AppKit's first-matching-
/// destination-wins-the-session rule lets the main capture intercept
/// drawer-source drags and silence the drawer for the entire session.
///
/// These assertions stay at the policy/value layer to avoid creating
/// raw NSView instances in tests, which interact with process-global
/// AppKit state and can pollute neighbouring suites.
@MainActor
@Suite(.serialized)
struct FlatTabStripContainerDragOwnershipTests {
    private static let nonEmptyFrame = NSRect(x: 0, y: 0, width: 400, height: 300)

    @Test
    func drawerExpanded_disablesMain_andEnablesDrawerCapture() {
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

        #expect(!mainEnabled)
        #expect(drawerEnabled)
    }

    @Test
    func drawerCollapsed_enablesMain_andDisablesDrawerCapture() {
        let mainEnabled = DrawerDragOwnershipPolicy.mainSplitDragEnabled(
            managementLayerActive: true,
            expandedDrawerParentPaneId: nil
        )
        let drawerEnabled = DrawerDragOwnershipPolicy.drawerCaptureEnabled(
            managementLayerActive: true,
            expandedDrawerParentPaneId: nil,
            drawerPanelFrameInTab: Self.nonEmptyFrame
        )

        #expect(mainEnabled)
        #expect(!drawerEnabled)
    }

    @Test
    func managementLayerInactive_disablesBothCaptures() {
        let parentPaneId = UUID()

        let mainEnabledNoDrawer = DrawerDragOwnershipPolicy.mainSplitDragEnabled(
            managementLayerActive: false,
            expandedDrawerParentPaneId: nil
        )
        let mainEnabledWithDrawer = DrawerDragOwnershipPolicy.mainSplitDragEnabled(
            managementLayerActive: false,
            expandedDrawerParentPaneId: parentPaneId
        )
        let drawerEnabled = DrawerDragOwnershipPolicy.drawerCaptureEnabled(
            managementLayerActive: false,
            expandedDrawerParentPaneId: parentPaneId,
            drawerPanelFrameInTab: Self.nonEmptyFrame
        )

        #expect(!mainEnabledNoDrawer)
        #expect(!mainEnabledWithDrawer)
        #expect(!drawerEnabled)
    }

    @Test
    func drawerCaptureRequiresNonEmptyPanelFrame() {
        let parentPaneId = UUID()

        let drawerEnabledEmpty = DrawerDragOwnershipPolicy.drawerCaptureEnabled(
            managementLayerActive: true,
            expandedDrawerParentPaneId: parentPaneId,
            drawerPanelFrameInTab: .zero
        )
        let drawerEnabledNonEmpty = DrawerDragOwnershipPolicy.drawerCaptureEnabled(
            managementLayerActive: true,
            expandedDrawerParentPaneId: parentPaneId,
            drawerPanelFrameInTab: Self.nonEmptyFrame
        )

        #expect(!drawerEnabledEmpty)
        #expect(drawerEnabledNonEmpty)
    }
}
