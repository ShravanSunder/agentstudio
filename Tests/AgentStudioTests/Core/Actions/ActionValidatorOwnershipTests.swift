import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct ActionValidatorOwnershipTests {
    private func makeSnapshot(
        tabs: [TabSnapshot],
        activeTabId: UUID? = nil,
        isManagementModeActive: Bool = false
    ) -> ActionStateSnapshot {
        ActionStateSnapshot(
            tabs: tabs,
            activeTabId: activeTabId,
            isManagementModeActive: isManagementModeActive
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

        let result = ActionValidator.validate(
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

        let result = ActionValidator.validate(
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
    func focusPane_hiddenOwnedPane_fails() {
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

        let result = ActionValidator.validate(
            .focusPane(tabId: tabId, paneId: hiddenPaneId),
            state: snapshot
        )

        if case .failure(.paneNotFound) = result { return }
        Issue.record("Expected paneNotFound error")
    }

    @Test
    func insertPane_hiddenOwnedSource_visibleTarget_succeeds() {
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
        let action = PaneActionCommand.insertPane(
            source: .existingPane(paneId: hiddenSourcePaneId, sourceTabId: sourceTabId),
            targetTabId: targetTabId,
            targetPaneId: targetPaneId,
            direction: .right
        )

        let result = ActionValidator.validate(action, state: snapshot)

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

        let result = ActionValidator.validate(
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

        let result = ActionValidator.validate(
            .toggleDrawer(paneId: hiddenParentPaneId),
            state: snapshot
        )

        if case .failure(.paneNotFound) = result { return }
        Issue.record("Expected paneNotFound error")
    }
}
