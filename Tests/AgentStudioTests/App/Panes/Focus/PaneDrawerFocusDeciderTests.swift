import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct PaneDrawerFocusDeciderTests {
    @Test("drawer toggle focuses active drawer pane when one is visible")
    func drawerToggle_focusesActiveDrawerPaneWhenVisible() {
        let parentPaneId = UUID()
        let drawerPaneId = UUID()

        let decision = PaneDrawerFocusDecider.decide(
            trigger: .toggle(parentPaneId: parentPaneId),
            context: PaneFocusContext(
                activeTabId: UUID(),
                activePaneId: parentPaneId,
                activeDrawerParentPaneId: parentPaneId,
                activeDrawerPaneId: drawerPaneId,
                targetPaneId: parentPaneId,
                targetTabId: UUID(),
                targetPaneKind: .terminal,
                targetPaneIsAlreadyActive: true,
                targetMountedContent: .terminal(surfaceId: UUID()),
                managementMode: .inactive,
                windowState: .key,
                triggerSource: .drawerClick
            )
        )

        #expect(decision.responder == .focusPaneHost(paneId: drawerPaneId))
    }
}
