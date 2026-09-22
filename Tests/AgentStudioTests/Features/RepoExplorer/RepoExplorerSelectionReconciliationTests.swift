import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@Suite("RepoExplorerSelectionReconciliationTests")
struct RepoExplorerSelectionReconciliationTests {
    @Test("exact selectable identity wins before an earlier duplicate destination representation")
    func exactSelectableIdentityWinsBeforeSemanticDuplicate() {
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let exactGroupID = "group:exact"
        let earlierGroupID = "group:earlier"
        let priorRowID = RepoExplorerRowID.associatedPane(
            groupID: exactGroupID,
            repoID: repositoryID,
            worktreeID: worktreeID,
            paneID: paneID
        )
        let previous = navigationSnapshot([
            .group(id: exactGroupID, expanded: true),
            .associatedPane(
                RepoExplorerNavigationAssociatedPaneTestRow(
                    groupID: exactGroupID,
                    repositoryID: repositoryID,
                    worktreeID: worktreeID,
                    paneID: paneID,
                    tabID: tabID
                )
            ),
        ])
        let current = navigationSnapshot([
            .group(id: earlierGroupID, expanded: true),
            .tabPane(groupID: earlierGroupID, paneID: paneID, tabID: tabID),
            .group(id: exactGroupID, expanded: true),
            .associatedPane(
                RepoExplorerNavigationAssociatedPaneTestRow(
                    groupID: exactGroupID,
                    repositoryID: repositoryID,
                    worktreeID: worktreeID,
                    paneID: paneID,
                    tabID: tabID
                )
            ),
        ])

        let reconciliation = selectionReconciliation(previous: previous, current: current)
        #expect(reconciliation.targetRowID(for: priorRowID) == priorRowID)
    }

    @Test("worktrees and panes follow semantic identity across representation changes")
    func destinationsFollowSemanticIdentityAcrossRepresentationChanges() {
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let oldWorktreeRowID = RepoExplorerRowID.worktree(
            groupID: "group:repository",
            repoID: repositoryID,
            worktreeID: worktreeID
        )
        let newWorktreeRowID = RepoExplorerRowID.worktree(
            groupID: "group:pinned",
            repoID: repositoryID,
            worktreeID: worktreeID
        )
        let oldAssociatedRowID = RepoExplorerRowID.associatedPane(
            groupID: "group:associated",
            repoID: repositoryID,
            worktreeID: worktreeID,
            paneID: paneID
        )
        let tabPaneRowID = RepoExplorerRowID.tabPane(groupID: "group:tab", paneID: paneID)
        let standalonePaneRowID = RepoExplorerRowID.unassociatedPane(paneID: paneID)
        let previous = navigationSnapshot([
            .worktree(groupID: "group:repository", repositoryID: repositoryID, worktreeID: worktreeID),
            .associatedPane(
                RepoExplorerNavigationAssociatedPaneTestRow(
                    groupID: "group:associated",
                    repositoryID: repositoryID,
                    worktreeID: worktreeID,
                    paneID: paneID,
                    tabID: tabID
                )
            ),
            .tabPane(groupID: "group:old-tab", paneID: paneID, tabID: tabID),
        ])
        let regrouped = navigationSnapshot([
            .worktree(groupID: "group:pinned", repositoryID: repositoryID, worktreeID: worktreeID),
            .tabPane(groupID: "group:tab", paneID: paneID, tabID: tabID),
        ])
        let standalone = navigationSnapshot([
            .unassociatedPane(paneID: paneID, tabID: tabID)
        ])

        let regroupedReconciliation = selectionReconciliation(previous: previous, current: regrouped)
        #expect(regroupedReconciliation.targetRowID(for: oldWorktreeRowID) == newWorktreeRowID)
        #expect(regroupedReconciliation.targetRowID(for: oldAssociatedRowID) == tabPaneRowID)

        let tabPriorRowID = RepoExplorerRowID.tabPane(groupID: "group:old-tab", paneID: paneID)
        let standaloneReconciliation = selectionReconciliation(previous: previous, current: standalone)
        #expect(standaloneReconciliation.targetRowID(for: tabPriorRowID) == standalonePaneRowID)
    }

    @Test("semantic translation chooses the first duplicate representation in current order")
    func semanticTranslationChoosesFirstCurrentRepresentation() {
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let priorRowID = RepoExplorerRowID.associatedPane(
            groupID: "group:old",
            repoID: repositoryID,
            worktreeID: worktreeID,
            paneID: paneID
        )
        let firstCurrentRowID = RepoExplorerRowID.tabPane(groupID: "group:first", paneID: paneID)
        let previous = navigationSnapshot([
            .associatedPane(
                RepoExplorerNavigationAssociatedPaneTestRow(
                    groupID: "group:old",
                    repositoryID: repositoryID,
                    worktreeID: worktreeID,
                    paneID: paneID,
                    tabID: tabID
                )
            )
        ])
        let current = navigationSnapshot([
            .tabPane(groupID: "group:first", paneID: paneID, tabID: tabID),
            .unassociatedPane(paneID: paneID, tabID: tabID),
        ])

        let reconciliation = selectionReconciliation(previous: previous, current: current)
        #expect(reconciliation.targetRowID(for: priorRowID) == firstCurrentRowID)
    }

    @Test("true removal uses translated successor then predecessor then current initial selection")
    func trueRemovalUsesOrderedFallbacks() {
        let tabID = UUIDv7.generate()
        let removedPaneID = UUIDv7.generate()
        let predecessorPaneID = UUIDv7.generate()
        let successorPaneID = UUIDv7.generate()
        let replacementPaneID = UUIDv7.generate()
        let removedRowID = RepoExplorerRowID.unassociatedPane(paneID: removedPaneID)
        let terminalRemovedRowID = RepoExplorerRowID.unassociatedPane(paneID: successorPaneID)
        let translatedSuccessorRowID = RepoExplorerRowID.tabPane(
            groupID: "group:successor",
            paneID: successorPaneID
        )
        let predecessorRowID = RepoExplorerRowID.unassociatedPane(paneID: predecessorPaneID)
        let previous = navigationSnapshot([
            .unassociatedPane(paneID: predecessorPaneID, tabID: tabID),
            .unassociatedPane(paneID: removedPaneID, tabID: tabID),
            .section(.panes),
            .activity(groupID: "group:static", bucket: .older),
            .unassociatedPane(paneID: successorPaneID, tabID: tabID),
        ])
        let successorCurrent = navigationSnapshot([
            .tabPane(groupID: "group:successor", paneID: successorPaneID, tabID: tabID),
            .unassociatedPane(paneID: predecessorPaneID, tabID: tabID),
        ])
        let predecessorCurrent = navigationSnapshot([
            .unassociatedPane(paneID: predecessorPaneID, tabID: tabID)
        ])
        let initialCurrent = navigationSnapshot([
            .group(id: "group:initial", expanded: false),
            .unassociatedPane(paneID: replacementPaneID, tabID: tabID),
        ])

        #expect(
            selectionReconciliation(previous: previous, current: successorCurrent)
                .targetRowID(for: removedRowID) == translatedSuccessorRowID
        )
        #expect(
            selectionReconciliation(previous: previous, current: predecessorCurrent)
                .targetRowID(for: terminalRemovedRowID) == predecessorRowID
        )
        #expect(
            selectionReconciliation(
                previous: navigationSnapshot([.unassociatedPane(paneID: removedPaneID, tabID: tabID)]),
                current: initialCurrent
            ).targetRowID(for: removedRowID) == .unassociatedPane(paneID: replacementPaneID)
        )
    }

    @Test("groups reconcile exactly and omitted rows never become removal fallbacks")
    func groupsAndOmittedRowsRespectSelectableOrder() {
        let retainedGroupRowID = RepoExplorerRowID.group(groupID: "group:retained")
        let removedGroupRowID = RepoExplorerRowID.group(groupID: "group:removed")
        let successorGroupRowID = RepoExplorerRowID.group(groupID: "group:successor")
        let previous = navigationSnapshot([
            .group(id: "group:retained", expanded: false),
            .group(id: "group:removed", expanded: false),
            .loadingSection(.repositories),
            .loadingRepository(section: .repositories, repositoryID: UUIDv7.generate()),
            .topologyFault,
            .unresolved(rowID: .loadingSectionHeader(.panes)),
            .group(id: "group:successor", expanded: false),
        ])
        let current = navigationSnapshot([
            .section(.repositories),
            .group(id: "group:successor", expanded: false),
            .group(id: "group:retained", expanded: false),
        ])
        let reconciliation = selectionReconciliation(previous: previous, current: current)

        #expect(reconciliation.targetRowID(for: retainedGroupRowID) == retainedGroupRowID)
        #expect(reconciliation.targetRowID(for: removedGroupRowID) == successorGroupRowID)
    }

    @Test("nil and unknown selections use current initial while empty current content clears selection")
    func initialAndEmptyTransitions() {
        let tabID = UUIDv7.generate()
        let currentPaneID = UUIDv7.generate()
        let priorPaneID = UUIDv7.generate()
        let current = navigationSnapshot([
            .group(id: "group:before-destination", expanded: false),
            .unassociatedPane(paneID: currentPaneID, tabID: tabID),
        ])
        let previous = navigationSnapshot([
            .unassociatedPane(paneID: priorPaneID, tabID: tabID)
        ])
        let expectedInitialRowID = RepoExplorerRowID.unassociatedPane(paneID: currentPaneID)
        let populatedReconciliation = selectionReconciliation(previous: .empty, current: current)
        let emptyReconciliation = selectionReconciliation(previous: previous, current: .empty)

        #expect(populatedReconciliation.targetRowID(for: nil) == expectedInitialRowID)
        #expect(
            populatedReconciliation.targetRowID(for: .group(groupID: "group:unknown"))
                == expectedInitialRowID
        )
        #expect(
            emptyReconciliation.targetRowID(
                for: .unassociatedPane(paneID: priorPaneID)
            ) == nil
        )
        #expect(emptyReconciliation.targetRowID(for: nil) == nil)
    }
}

private func selectionReconciliation(
    previous: RepoExplorerMaterializationSnapshot,
    current: RepoExplorerMaterializationSnapshot
) -> RepoExplorerSelectionReconciliation {
    RepoExplorerSelectionReconciliation(
        previous: previous.navigationIndex,
        current: current.navigationIndex
    )
}
