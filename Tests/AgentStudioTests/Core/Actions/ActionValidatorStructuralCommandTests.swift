import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct ActionValidatorStructuralCommandTests {
    @Test("structural split commands validate against layout split even when one pane is hidden")
    func structuralSplitCommandsUseLayoutSplit() {
        let tabId = UUID()
        let primaryPaneId = UUIDv7.generate()
        let hiddenPaneId = UUIDv7.generate()
        let tab = makeSplitTabWithHiddenPane(
            tabId: tabId,
            primaryPaneId: primaryPaneId,
            hiddenPaneId: hiddenPaneId
        )
        let snapshot = WorkspaceCommandResolver.snapshot(
            from: [tab],
            activeTabId: tabId,
            isManagementLayerActive: false,
            visiblePaneIds: { _ in [primaryPaneId] }
        )

        let breakUpResult = WorkspaceCommandValidator.validate(.breakUpTab(tabId: tabId), state: snapshot)
        let equalizeResult = WorkspaceCommandValidator.validate(.equalizePanes(tabId: tabId), state: snapshot)

        #expect((try? breakUpResult.get()) != nil)
        #expect((try? equalizeResult.get()) != nil)
    }

    @Test("existing pane insert request allows same-tab pane moves")
    func existingPaneInsertAllowsSameTabPaneMoves() {
        let tabId = UUID()
        let sourcePaneId = UUIDv7.generate()
        let targetPaneId = UUIDv7.generate()
        let snapshot = ActionStateSnapshot(
            tabs: [
                TabSnapshot(
                    id: tabId,
                    visiblePaneIds: [sourcePaneId, targetPaneId],
                    ownedPaneIds: [sourcePaneId, targetPaneId],
                    activePaneId: sourcePaneId
                )
            ],
            activeTabId: tabId,
            isManagementLayerActive: false
        )

        let result = WorkspaceCommandValidator.validate(
            .insertPane(
                source: .existingPane(paneId: sourcePaneId, sourceTabId: tabId),
                targetTabId: tabId,
                targetPaneId: targetPaneId,
                direction: .right,
                sizingMode: .halveTarget
            ),
            state: snapshot
        )

        #expect((try? result.get()) != nil)
    }

    private func makeSplitTabWithHiddenPane(
        tabId: UUID,
        primaryPaneId: UUID,
        hiddenPaneId: UUID
    ) -> Tab {
        let layout = Layout.autoTiled([primaryPaneId, hiddenPaneId])
        let arrangement = PaneArrangement(
            layout: layout,
            minimizedPaneIds: [hiddenPaneId],
            showsMinimizedPanes: false,
            activePaneId: primaryPaneId
        )
        return Tab(
            id: tabId,
            allPaneIds: [primaryPaneId, hiddenPaneId],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )
    }
}
