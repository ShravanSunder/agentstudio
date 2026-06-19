import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct WorkspaceCommandValidatorOwnershipTests {
    private func makeSnapshot(
        tabs: [TabSnapshot],
        activeTabId: UUID? = nil,
        isManagementLayerActive: Bool = false,
        drawerParentByPaneId: [UUID: UUID] = [:],
        drawerLayoutByParentPaneId: [UUID: DrawerGridLayout] = [:]
    ) -> ActionStateSnapshot {
        ActionStateSnapshot(
            tabs: tabs,
            activeTabId: activeTabId,
            isManagementLayerActive: isManagementLayerActive,
            drawerParentByPaneId: drawerParentByPaneId,
            drawerLayoutByParentPaneId: drawerLayoutByParentPaneId
        )
    }

    @Test
    func closePane_hiddenOwnedPane_succeedsWithoutCanonicalizingToCloseTab() {
        let tabId = UUID()
        let visiblePaneId = UUIDv7.generate()
        let hiddenPaneId = UUIDv7.generate()
        let snapshot = makeSnapshot(
            tabs: [
                TabSnapshot(
                    id: tabId,
                    visiblePaneIds: [visiblePaneId],
                    ownedPaneIds: [visiblePaneId, hiddenPaneId],
                    activePaneId: visiblePaneId
                )
            ]
        )

        let result = WorkspaceCommandValidator.validate(
            .closePane(tabId: tabId, paneId: hiddenPaneId),
            state: snapshot
        )

        guard case .success(let validated) = result else {
            Issue.record("Expected success")
            return
        }
        #expect(validated.action == .closePane(tabId: tabId, paneId: hiddenPaneId))
    }

    @Test
    func closePane_visiblePaneWithHiddenOwnedSibling_succeedsWithoutCanonicalizingToCloseTab() {
        let tabId = UUID()
        let visiblePaneId = UUIDv7.generate()
        let hiddenPaneId = UUIDv7.generate()
        let snapshot = makeSnapshot(
            tabs: [
                TabSnapshot(
                    id: tabId,
                    visiblePaneIds: [visiblePaneId],
                    ownedPaneIds: [visiblePaneId, hiddenPaneId],
                    activePaneId: visiblePaneId
                )
            ]
        )

        let result = WorkspaceCommandValidator.validate(
            .closePane(tabId: tabId, paneId: visiblePaneId),
            state: snapshot
        )

        guard case .success(let validated) = result else {
            Issue.record("Expected success")
            return
        }
        #expect(validated.action == .closePane(tabId: tabId, paneId: visiblePaneId))
    }

    @Test
    func movePaneAcrossTabs_hiddenOwnedSource_visibleTarget_succeeds() {
        let sourceTabId = UUID()
        let visibleSourcePaneId = UUIDv7.generate()
        let hiddenSourcePaneId = UUIDv7.generate()
        let targetTabId = UUID()
        let targetPaneId = UUIDv7.generate()
        let snapshot = makeSnapshot(
            tabs: [
                TabSnapshot(
                    id: sourceTabId,
                    visiblePaneIds: [visibleSourcePaneId],
                    ownedPaneIds: [visibleSourcePaneId, hiddenSourcePaneId],
                    activePaneId: visibleSourcePaneId
                ),
                TabSnapshot(
                    id: targetTabId,
                    visiblePaneIds: [targetPaneId],
                    ownedPaneIds: [targetPaneId],
                    activePaneId: targetPaneId
                ),
            ]
        )
        let action = WorkspaceActionCommand.movePaneAcrossTabs(
            CrossTabPaneMoveRequest(
                paneId: hiddenSourcePaneId,
                sourceTabId: sourceTabId,
                destTabId: targetTabId,
                targetPaneId: targetPaneId,
                direction: .horizontal,
                position: .after
            )
        )

        let result = WorkspaceCommandValidator.validate(action, state: snapshot)

        #expect((try? result.get()) != nil)
    }

    @Test
    func removeDrawerPane_hiddenOwnedParent_succeeds() {
        let tabId = UUID()
        let visiblePaneId = UUIDv7.generate()
        let hiddenParentPaneId = UUIDv7.generate()
        let snapshot = makeSnapshot(
            tabs: [
                TabSnapshot(
                    id: tabId,
                    visiblePaneIds: [visiblePaneId],
                    ownedPaneIds: [visiblePaneId, hiddenParentPaneId],
                    activePaneId: visiblePaneId
                )
            ]
        )

        let result = WorkspaceCommandValidator.validate(
            .removeDrawerPane(parentPaneId: hiddenParentPaneId, drawerPaneId: UUIDv7.generate()),
            state: snapshot
        )

        #expect((try? result.get()) != nil)
    }

    @Test
    func toggleDrawer_hiddenOwnedParent_fails() {
        let tabId = UUID()
        let visiblePaneId = UUIDv7.generate()
        let hiddenParentPaneId = UUIDv7.generate()
        let snapshot = makeSnapshot(
            tabs: [
                TabSnapshot(
                    id: tabId,
                    visiblePaneIds: [visiblePaneId],
                    ownedPaneIds: [visiblePaneId, hiddenParentPaneId],
                    activePaneId: visiblePaneId
                )
            ]
        )

        let result = WorkspaceCommandValidator.validate(
            .toggleDrawer(paneId: hiddenParentPaneId),
            state: snapshot
        )

        if case .failure(.paneNotFound) = result { return }
        Issue.record("Expected paneNotFound error")
    }

    @Test
    func moveDrawerPane_invalidDrawerLayoutFails() {
        let parentPaneId = UUIDv7.generate()
        let drawerPaneId = UUIDv7.generate()
        let snapshot = makeSnapshot(
            tabs: [
                TabSnapshot(
                    id: UUID(),
                    visiblePaneIds: [parentPaneId],
                    ownedPaneIds: [parentPaneId, drawerPaneId],
                    activePaneId: parentPaneId
                )
            ],
            isManagementLayerActive: true,
            drawerParentByPaneId: [drawerPaneId: parentPaneId]
        )

        let result = DrawerCommandValidator.validateResultingLayout(
            DrawerGridLayout(
                topRow: Layout.autoTiled([UUID()]),
                bottomRow: Layout.autoTiled([UUID()])
            ),
            parentPaneId: parentPaneId,
            state: snapshot,
            requestedDirection: .down,
            wouldCreateThirdRow: true
        )

        if case .failure(
            .invalidDrawerLayout(parentPaneId: parentPaneId, reason: .resultingLayoutWouldCreateThirdRow)
        ) = result {
            return
        }
        Issue.record("Expected invalidDrawerLayout when a drawer edit would create a third row")
    }

    @Test
    func detachDrawerPane_hiddenParentFailsValidation() {
        let parentPaneId = UUIDv7.generate()
        let drawerPaneId = UUIDv7.generate()
        let snapshot = makeSnapshot(
            tabs: [
                TabSnapshot(
                    id: UUID(),
                    visiblePaneIds: [],
                    ownedPaneIds: [parentPaneId, drawerPaneId],
                    activePaneId: nil
                )
            ],
            drawerParentByPaneId: [drawerPaneId: parentPaneId],
            drawerLayoutByParentPaneId: [
                parentPaneId: DrawerGridLayout(topRow: Layout.autoTiled([drawerPaneId]))
            ]
        )

        let result = WorkspaceCommandValidator.validate(
            .detachDrawerPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId),
            state: snapshot
        )

        if case .failure(.paneNotFound) = result { return }
        Issue.record("Expected paneNotFound when parent is not showing in active arrangement")
    }
}
