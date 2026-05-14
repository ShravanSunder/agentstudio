import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct PaneInteractionOcclusionPolicyTests {
    @Test
    func expandedDrawer_suppressesMainPaneInteraction() {
        #expect(
            PaneInteractionOcclusionPolicy.suppressMainPaneManagementInteraction(
                isDrawerChild: false,
                tabContainsExpandedDrawer: true
            )
        )
    }

    @Test
    func expandedDrawer_doesNotSuppressDrawerChildInteraction() {
        #expect(
            !PaneInteractionOcclusionPolicy.suppressMainPaneManagementInteraction(
                isDrawerChild: true,
                tabContainsExpandedDrawer: true
            )
        )
    }

    @Test
    func noExpandedDrawer_doesNotSuppressMainPaneInteraction() {
        #expect(
            !PaneInteractionOcclusionPolicy.suppressMainPaneManagementInteraction(
                isDrawerChild: false,
                tabContainsExpandedDrawer: false
            )
        )
    }
}
