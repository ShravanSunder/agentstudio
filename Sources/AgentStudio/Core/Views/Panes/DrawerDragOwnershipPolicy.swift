import CoreGraphics
import Foundation

@MainActor
enum DrawerDragOwnershipPolicy {
    static func expandedDrawerParentPaneId(
        tabId: UUID,
        tabLayoutAtom: WorkspaceTabLayoutAtom,
        paneAtom: WorkspacePaneAtom
    ) -> UUID? {
        guard let tab = tabLayoutAtom.tab(tabId) else { return nil }

        for paneId in tab.paneIds where paneAtom.pane(paneId)?.drawer?.isExpanded == true {
            return paneId
        }

        return nil
    }

    static func mainSplitDragEnabled(
        managementLayerActive: Bool,
        expandedDrawerParentPaneId: UUID?
    ) -> Bool {
        managementLayerActive
    }

    static func drawerCaptureEnabled(
        managementLayerActive: Bool,
        expandedDrawerParentPaneId: UUID?,
        drawerPanelFrameInTab: CGRect
    ) -> Bool {
        managementLayerActive && expandedDrawerParentPaneId != nil && !drawerPanelFrameInTab.isEmpty
    }

    static func retainedDrawerDropTarget(
        _ target: DrawerRearrangeTarget?,
        expandedDrawerParentPaneId: UUID?
    ) -> DrawerRearrangeTarget? {
        expandedDrawerParentPaneId == nil ? nil : target
    }
}
