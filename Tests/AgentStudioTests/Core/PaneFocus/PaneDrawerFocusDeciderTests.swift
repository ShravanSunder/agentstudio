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
                activeDrawer: .init(parentPaneId: parentPaneId, paneId: drawerPaneId),
                targetPaneId: parentPaneId,
                targetTabId: UUID(),
                targetPaneKind: .terminal,
                targetPaneIsAlreadyActive: true,
                targetMountedContent: .terminal(surfaceId: UUID()),
                managementLayer: .inactive,
                windowState: .key
            )
        )

        #expect(decision.responder == .focusPaneHost(paneId: drawerPaneId))
    }

    @Test("drawer pane selection focuses selected drawer pane")
    func drawerSelectPane_focusesSelectedDrawerPane() {
        let parentPaneId = UUID()
        let drawerPaneId = UUID()

        let decision = PaneDrawerFocusDecider.decide(
            trigger: .selectPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId),
            context: PaneFocusContext(
                activeTabId: UUID(),
                activePaneId: parentPaneId,
                activeDrawer: .init(parentPaneId: parentPaneId, paneId: drawerPaneId),
                targetPaneId: drawerPaneId,
                targetTabId: UUID(),
                targetPaneKind: .terminal,
                targetPaneIsAlreadyActive: false,
                targetMountedContent: .terminal(surfaceId: UUID()),
                managementLayer: .inactive,
                windowState: .key
            )
        )

        #expect(decision.selection == .selectDrawerPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId))
        #expect(decision.responder == .focusPaneHost(paneId: drawerPaneId))
    }
}
