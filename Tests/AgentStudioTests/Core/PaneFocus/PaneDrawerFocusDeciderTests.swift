import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

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

    @Test("drawer pane selection keeps selection when that drawer pane is already active")
    func drawerSelectPane_keepsSelectionWhenAlreadyActive() {
        let parentPaneId = UUID()
        let drawerPaneId = UUID()

        let decision = PaneDrawerFocusDecider.decide(
            trigger: .selectPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId),
            context: PaneFocusContext(
                activeTabId: UUID(),
                activePaneId: drawerPaneId,
                activeDrawer: .init(parentPaneId: parentPaneId, paneId: drawerPaneId),
                targetPaneId: drawerPaneId,
                targetTabId: UUID(),
                targetPaneKind: .terminal,
                targetPaneIsAlreadyActive: true,
                targetMountedContent: .terminal(surfaceId: UUID()),
                managementLayer: .inactive,
                windowState: .key
            )
        )

        #expect(decision.selection == .keep)
        #expect(decision.responder == .focusPaneHost(paneId: drawerPaneId))
        #expect(decision.runtime == .preserveRuntimeFocus)
    }

    @Test("drawer pane selection selects the drawer's active child when focus is still on the main pane")
    func drawerSelectPane_selectsActiveChildWhenFocusIsOnMainPane() {
        let parentPaneId = UUIDv7.generate()
        let drawerPaneId = UUIDv7.generate()

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

        #expect(
            decision.selection
                == .selectDrawerPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)
        )
        #expect(decision.responder == .focusPaneHost(paneId: drawerPaneId))
        #expect(decision.runtime == .preserveRuntimeFocus)
    }

    @Test("drawer pane selection selects a different drawer pane")
    func drawerSelectPane_selectsDifferentDrawerPane() {
        let parentPaneId = UUID()
        let currentDrawerPaneId = UUID()
        let otherDrawerPaneId = UUID()

        let decision = PaneDrawerFocusDecider.decide(
            trigger: .selectPane(parentPaneId: parentPaneId, drawerPaneId: otherDrawerPaneId),
            context: PaneFocusContext(
                activeTabId: UUID(),
                activePaneId: parentPaneId,
                activeDrawer: .init(parentPaneId: parentPaneId, paneId: currentDrawerPaneId),
                targetPaneId: otherDrawerPaneId,
                targetTabId: UUID(),
                targetPaneKind: .terminal,
                targetPaneIsAlreadyActive: false,
                targetMountedContent: .terminal(surfaceId: UUID()),
                managementLayer: .inactive,
                windowState: .key
            )
        )

        #expect(
            decision.selection
                == .selectDrawerPane(parentPaneId: parentPaneId, drawerPaneId: otherDrawerPaneId)
        )
    }
}
