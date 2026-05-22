import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct ActionValidatorCrossTabPaneMoveTests {
    @Test
    func validMainPane_succeeds() {
        let sourcePaneId = UUID()
        let targetPaneId = UUID()
        let sourceTabId = UUID()
        let targetTabId = UUID()
        let sourceTab = TabSnapshot(
            id: sourceTabId,
            visiblePaneIds: [sourcePaneId],
            ownedPaneIds: [sourcePaneId],
            activePaneId: sourcePaneId
        )
        let targetTab = TabSnapshot(
            id: targetTabId,
            visiblePaneIds: [targetPaneId],
            ownedPaneIds: [targetPaneId],
            activePaneId: targetPaneId
        )
        let snapshot = makeSnapshot(tabs: [sourceTab, targetTab])

        let result = WorkspaceCommandValidator.validate(
            moveRequest(
                paneId: sourcePaneId,
                sourceTabId: sourceTabId,
                destTabId: targetTabId,
                targetPaneId: targetPaneId
            ),
            state: snapshot
        )

        #expect((try? result.get()) != nil)
    }

    @Test
    func drawerChild_fails() {
        let parentPaneId = UUID()
        let drawerPaneId = UUID()
        let targetPaneId = UUID()
        let sourceTabId = UUID()
        let targetTabId = UUID()
        let sourceTab = TabSnapshot(
            id: sourceTabId,
            visiblePaneIds: [parentPaneId],
            ownedPaneIds: [parentPaneId, drawerPaneId],
            activePaneId: parentPaneId
        )
        let targetTab = TabSnapshot(
            id: targetTabId,
            visiblePaneIds: [targetPaneId],
            ownedPaneIds: [targetPaneId],
            activePaneId: targetPaneId
        )
        let snapshot = makeSnapshot(
            tabs: [sourceTab, targetTab],
            drawerParentByPaneId: [drawerPaneId: parentPaneId]
        )

        let result = WorkspaceCommandValidator.validate(
            moveRequest(
                paneId: drawerPaneId,
                sourceTabId: sourceTabId,
                destTabId: targetTabId,
                targetPaneId: targetPaneId
            ),
            state: snapshot
        )

        if case .failure(.drawerPaneCannotCrossTabs) = result { return }
        Issue.record("Expected drawerPaneCannotCrossTabs error")
    }

    @Test
    func sameTab_fails() {
        let paneId = UUID()
        let targetPaneId = UUID()
        let tabId = UUID()
        let tab = TabSnapshot(
            id: tabId,
            visiblePaneIds: [paneId, targetPaneId],
            ownedPaneIds: [paneId, targetPaneId],
            activePaneId: paneId
        )
        let snapshot = makeSnapshot(tabs: [tab])

        let result = WorkspaceCommandValidator.validate(
            moveRequest(
                paneId: paneId,
                sourceTabId: tabId,
                destTabId: tabId,
                targetPaneId: targetPaneId
            ),
            state: snapshot
        )

        if case .failure(.crossTabSameTab) = result { return }
        Issue.record("Expected crossTabSameTab error")
    }

    private func makeSnapshot(
        tabs: [TabSnapshot],
        drawerParentByPaneId: [UUID: UUID] = [:]
    ) -> ActionStateSnapshot {
        ActionStateSnapshot(
            tabs: tabs,
            activeTabId: tabs.first?.id,
            isManagementLayerActive: false,
            drawerParentByPaneId: drawerParentByPaneId
        )
    }

    private func moveRequest(
        paneId: UUID,
        sourceTabId: UUID,
        destTabId: UUID,
        targetPaneId: UUID
    ) -> PaneActionCommand {
        .movePaneAcrossTabs(
            CrossTabPaneMoveRequest(
                paneId: paneId,
                sourceTabId: sourceTabId,
                destTabId: destTabId,
                targetPaneId: targetPaneId,
                direction: .horizontal,
                position: .after
            )
        )
    }
}
