import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@Suite("RepoExplorerNavigationIndexTests")
struct RepoExplorerNavigationIndexTests {
    @Test("selectability and numbering exhaustively classify materialized presentations")
    func selectabilityAndNumberingClassifyEveryPresentation() {
        let groupID = "group:primary"
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let associatedPaneID = UUIDv7.generate()
        let unassociatedPaneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let staticRepositoryID = UUIDv7.generate()
        let unresolvedRowID = RepoExplorerRowID.loadingRepository(
            section: .repositories,
            repoID: UUIDv7.generate()
        )
        let groupRowID = RepoExplorerRowID.group(groupID: groupID)
        let worktreeRowID = RepoExplorerRowID.worktree(
            groupID: groupID,
            repoID: repositoryID,
            worktreeID: worktreeID
        )
        let paneRowID = RepoExplorerRowID.associatedPane(
            groupID: groupID,
            repoID: repositoryID,
            worktreeID: worktreeID,
            paneID: associatedPaneID
        )
        let unassociatedPaneRowID = RepoExplorerRowID.unassociatedPane(paneID: unassociatedPaneID)
        let snapshot = navigationSnapshot([
            .section(.repositories),
            .loadingSection(.repositories),
            .loadingRepository(section: .repositories, repositoryID: staticRepositoryID),
            .group(id: groupID, expanded: true),
            .activity(groupID: groupID, bucket: .active),
            .worktree(groupID: groupID, repositoryID: repositoryID, worktreeID: worktreeID),
            .associatedPane(
                RepoExplorerNavigationAssociatedPaneTestRow(
                    groupID: groupID,
                    repositoryID: repositoryID,
                    worktreeID: worktreeID,
                    paneID: associatedPaneID,
                    tabID: tabID
                )
            ),
            .unassociatedPane(paneID: unassociatedPaneID, tabID: tabID),
            .topologyFault,
            .unresolved(rowID: unresolvedRowID),
        ])

        #expect(
            snapshot.navigationIndex.selectableRowIDs == [
                groupRowID,
                worktreeRowID,
                paneRowID,
                unassociatedPaneRowID,
            ])
        #expect(snapshot.navigationIndex.initialSelectionRowID == worktreeRowID)
        #expect(
            snapshot.navigationIndex.numberedDestinationRowIDs == [
                worktreeRowID,
                paneRowID,
                unassociatedPaneRowID,
            ])
        #expect(snapshot.navigationIndex.destinationID(for: groupRowID) == nil)
        #expect(snapshot.navigationIndex.destinationID(for: worktreeRowID) == .worktree(worktreeID))
        #expect(snapshot.navigationIndex.destinationID(for: paneRowID) == .pane(associatedPaneID))
        #expect(snapshot.navigationIndex.destinationID(for: unassociatedPaneRowID) == .pane(unassociatedPaneID))
    }

    @Test("digits and numbered rows are inverse for only the first nine destinations")
    func digitsAndNumberedRowsAreInverseForFirstNineDestinations() {
        let tabID = UUIDv7.generate()
        let paneIDs = (0..<10).map { _ in UUIDv7.generate() }
        let snapshot = navigationSnapshot(
            paneIDs.map { paneID in
                .unassociatedPane(paneID: paneID, tabID: tabID)
            }
        )
        let expectedNumberedRows = paneIDs.prefix(9).map {
            RepoExplorerRowID.unassociatedPane(paneID: $0)
        }

        #expect(snapshot.navigationIndex.numberedDestinationRowIDs == expectedNumberedRows)
        for (zeroBasedIndex, rowID) in expectedNumberedRows.enumerated() {
            let digit = zeroBasedIndex + 1
            #expect(snapshot.navigationIndex.rowID(forDigit: digit) == rowID)
            #expect(snapshot.navigationIndex.digit(for: rowID) == digit)
        }
        #expect(snapshot.navigationIndex.rowID(forDigit: 0) == nil)
        #expect(snapshot.navigationIndex.rowID(forDigit: 10) == nil)
        #expect(snapshot.navigationIndex.digit(for: .unassociatedPane(paneID: paneIDs[9])) == nil)
    }

    @Test("previous and next selection stop at both edges")
    func previousAndNextSelectionStopAtEdges() {
        let firstGroupID = "group:first"
        let secondGroupID = "group:second"
        let paneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let firstRowID = RepoExplorerRowID.group(groupID: firstGroupID)
        let middleRowID = RepoExplorerRowID.unassociatedPane(paneID: paneID)
        let lastRowID = RepoExplorerRowID.group(groupID: secondGroupID)
        let unknownRowID = RepoExplorerRowID.group(groupID: "group:unknown")
        let snapshot = navigationSnapshot([
            .group(id: firstGroupID, expanded: false),
            .unassociatedPane(paneID: paneID, tabID: tabID),
            .group(id: secondGroupID, expanded: false),
        ])

        #expect(snapshot.navigationIndex.containsSelectableRow(firstRowID))
        #expect(snapshot.navigationIndex.containsSelectableRow(middleRowID))
        #expect(snapshot.navigationIndex.containsSelectableRow(lastRowID))
        #expect(!snapshot.navigationIndex.containsSelectableRow(unknownRowID))
        #expect(snapshot.navigationIndex.previousSelectableRowID(before: firstRowID) == nil)
        #expect(snapshot.navigationIndex.nextSelectableRowID(after: firstRowID) == middleRowID)
        #expect(snapshot.navigationIndex.previousSelectableRowID(before: middleRowID) == firstRowID)
        #expect(snapshot.navigationIndex.nextSelectableRowID(after: middleRowID) == lastRowID)
        #expect(snapshot.navigationIndex.previousSelectableRowID(before: lastRowID) == middleRowID)
        #expect(snapshot.navigationIndex.nextSelectableRowID(after: lastRowID) == nil)
        #expect(snapshot.navigationIndex.previousSelectableRowID(before: unknownRowID) == nil)
        #expect(snapshot.navigationIndex.nextSelectableRowID(after: unknownRowID) == nil)
    }

    @Test("group relationships use the first visible destination and skip activity labels")
    func groupRelationshipsUseFirstVisibleDestination() {
        let expandedGroupID = "group:expanded"
        let collapsedGroupID = "group:collapsed"
        let emptyGroupID = "group:empty"
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let childPaneID = UUIDv7.generate()
        let missingGroupPaneID = UUIDv7.generate()
        let standalonePaneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let expandedGroupRowID = RepoExplorerRowID.group(groupID: expandedGroupID)
        let worktreeRowID = RepoExplorerRowID.worktree(
            groupID: expandedGroupID,
            repoID: repositoryID,
            worktreeID: worktreeID
        )
        let childPaneRowID = RepoExplorerRowID.tabPane(
            groupID: expandedGroupID,
            paneID: childPaneID
        )
        let collapsedGroupRowID = RepoExplorerRowID.group(groupID: collapsedGroupID)
        let emptyGroupRowID = RepoExplorerRowID.group(groupID: emptyGroupID)
        let missingGroupPaneRowID = RepoExplorerRowID.tabPane(
            groupID: "group:missing",
            paneID: missingGroupPaneID
        )
        let standalonePaneRowID = RepoExplorerRowID.unassociatedPane(paneID: standalonePaneID)
        let snapshot = navigationSnapshot([
            .group(id: expandedGroupID, expanded: true),
            .activity(groupID: expandedGroupID, bucket: .justNow),
            .worktree(
                groupID: expandedGroupID,
                repositoryID: repositoryID,
                worktreeID: worktreeID
            ),
            .tabPane(groupID: expandedGroupID, paneID: childPaneID, tabID: tabID),
            .group(id: collapsedGroupID, expanded: false),
            .group(id: emptyGroupID, expanded: true),
            .tabPane(groupID: "group:missing", paneID: missingGroupPaneID, tabID: tabID),
            .unassociatedPane(paneID: standalonePaneID, tabID: tabID),
        ])

        #expect(snapshot.navigationIndex.firstChildRowID(for: expandedGroupRowID) == worktreeRowID)
        #expect(snapshot.navigationIndex.parentRowID(for: worktreeRowID) == expandedGroupRowID)
        #expect(snapshot.navigationIndex.parentRowID(for: childPaneRowID) == expandedGroupRowID)
        #expect(snapshot.navigationIndex.firstChildRowID(for: collapsedGroupRowID) == nil)
        #expect(snapshot.navigationIndex.firstChildRowID(for: emptyGroupRowID) == nil)
        #expect(snapshot.navigationIndex.parentRowID(for: missingGroupPaneRowID) == nil)
        #expect(snapshot.navigationIndex.parentRowID(for: standalonePaneRowID) == nil)
    }

    @Test("pane representations share one semantic destination and preserve first occurrence")
    func paneRepresentationsShareDestinationAndFirstOccurrence() {
        let associatedGroupID = "group:associated"
        let tabGroupID = "group:tab"
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let associatedRowID = RepoExplorerRowID.associatedPane(
            groupID: associatedGroupID,
            repoID: repositoryID,
            worktreeID: worktreeID,
            paneID: paneID
        )
        let tabRowID = RepoExplorerRowID.tabPane(groupID: tabGroupID, paneID: paneID)
        let standaloneRowID = RepoExplorerRowID.unassociatedPane(paneID: paneID)
        let paneDestinationID = RepoExplorerNavigationDestinationID.pane(paneID)
        let snapshot = navigationSnapshot([
            .group(id: associatedGroupID, expanded: true),
            .associatedPane(
                RepoExplorerNavigationAssociatedPaneTestRow(
                    groupID: associatedGroupID,
                    repositoryID: repositoryID,
                    worktreeID: worktreeID,
                    paneID: paneID,
                    tabID: tabID
                )
            ),
            .group(id: tabGroupID, expanded: true),
            .tabPane(groupID: tabGroupID, paneID: paneID, tabID: tabID),
            .unassociatedPane(paneID: paneID, tabID: tabID),
        ])

        #expect(snapshot.navigationIndex.destinationID(for: associatedRowID) == paneDestinationID)
        #expect(snapshot.navigationIndex.destinationID(for: tabRowID) == paneDestinationID)
        #expect(snapshot.navigationIndex.destinationID(for: standaloneRowID) == paneDestinationID)
        #expect(snapshot.navigationIndex.firstRowID(for: paneDestinationID) == associatedRowID)
    }

    @Test("initial selection prefers a destination and falls back to the first group")
    func initialSelectionPrefersDestinationThenFirstGroup() {
        let firstGroupID = "group:first"
        let secondGroupID = "group:second"
        let paneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let destinationSnapshot = navigationSnapshot([
            .group(id: firstGroupID, expanded: false),
            .group(id: secondGroupID, expanded: true),
            .tabPane(groupID: secondGroupID, paneID: paneID, tabID: tabID),
        ])
        let groupsOnlySnapshot = navigationSnapshot([
            .section(.panes),
            .group(id: firstGroupID, expanded: false),
            .group(id: secondGroupID, expanded: false),
        ])

        #expect(
            destinationSnapshot.navigationIndex.initialSelectionRowID
                == RepoExplorerRowID.tabPane(groupID: secondGroupID, paneID: paneID)
        )
        #expect(
            groupsOnlySnapshot.navigationIndex.initialSelectionRowID
                == RepoExplorerRowID.group(groupID: firstGroupID)
        )
        #expect(RepoExplorerMaterializationSnapshot.empty.navigationIndex.initialSelectionRowID == nil)
    }
}
