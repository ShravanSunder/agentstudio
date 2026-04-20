import Foundation

enum PaneInteractionOcclusionPolicy {
    static func suppressMainPaneManagementInteraction(
        isDrawerChild: Bool,
        tabContainsExpandedDrawer: Bool
    ) -> Bool {
        tabContainsExpandedDrawer && !isDrawerChild
    }
}
