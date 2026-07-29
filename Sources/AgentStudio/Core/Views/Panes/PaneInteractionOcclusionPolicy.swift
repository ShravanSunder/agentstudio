import Foundation

package enum PaneInteractionOcclusionPolicy {
    package static func suppressMainPaneManagementInteraction(
        isDrawerChild: Bool,
        tabContainsExpandedDrawer: Bool
    ) -> Bool {
        tabContainsExpandedDrawer && !isDrawerChild
    }
}
