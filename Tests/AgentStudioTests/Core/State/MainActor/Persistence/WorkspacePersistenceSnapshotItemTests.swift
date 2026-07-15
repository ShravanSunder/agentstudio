import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace persistence snapshot item contract")
struct WorkspacePersistenceSnapshotItemTests {
    @Test("participant inventory is exact and unique")
    func participantInventoryIsExactAndUnique() {
        // Arrange
        let expectedParticipants: [WorkspacePersistenceSnapshotParticipantID] = [
            .workspaceIdentity,
            .workspaceWindowMemory,
            .repositories,
            .worktrees,
            .watchedPaths,
            .unavailableRepositories,
            .paneGraphs,
            .expandedDrawer,
            .tabShells,
            .activeTab,
            .tabGraphs,
            .activeArrangements,
            .activePanes,
            .activeDrawerChildren,
        ]

        // Act
        let participants = WorkspacePersistenceSnapshotParticipantID.allCases

        // Assert
        #expect(participants == expectedParticipants)
        #expect(participants.count == 14)
        #expect(Set(participants).count == participants.count)
    }

    @Test("every item case maps to its exact participant and item identity")
    func everyItemCaseMapsToExactParticipantAndItemIdentity() {
        // Arrange
        let fixture = SnapshotItemFixture()
        let items: [WorkspacePersistenceSnapshotItem] = [
            .workspaceIdentity(fixture.workspaceIdentity),
            .windowMemory(fixture.windowMemory),
            .repository(fixture.repository),
            .worktree(fixture.worktree),
            .watchedPath(fixture.watchedPath),
            .unavailableRepository(fixture.unavailableRepositoryID),
            .paneGraph(fixture.paneGraph),
            .expandedDrawer(fixture.expandedDrawerID),
            .tabShell(fixture.persistedTabShell),
            .activeTab(fixture.activeTabID),
            .tabGraph(fixture.tabGraph),
            .activeArrangement(tabID: fixture.tabID, arrangementID: fixture.activeArrangementID),
            .activePane(arrangementID: fixture.arrangementID, paneID: fixture.activePaneID),
            .activeDrawerChild(key: fixture.drawerCursorKey, childPaneID: fixture.activeDrawerChildID),
        ]
        let expectedParticipantIDs: [WorkspacePersistenceSnapshotParticipantID] = [
            .workspaceIdentity,
            .workspaceWindowMemory,
            .repositories,
            .worktrees,
            .watchedPaths,
            .unavailableRepositories,
            .paneGraphs,
            .expandedDrawer,
            .tabShells,
            .activeTab,
            .tabGraphs,
            .activeArrangements,
            .activePanes,
            .activeDrawerChildren,
        ]
        let expectedItemIDs: [WorkspacePersistenceSnapshotItemID] = [
            .workspaceIdentity,
            .windowMemory,
            .repository(fixture.repository.id),
            .worktree(fixture.worktree.id),
            .watchedPath(fixture.watchedPath.id),
            .unavailableRepository(fixture.unavailableRepositoryID),
            .paneGraph(fixture.paneGraph.id),
            .expandedDrawer(fixture.expandedDrawerID),
            .tabShell(fixture.persistedTabShell.shell.id),
            .activeTab,
            .tabGraph(fixture.tabGraph.tabId),
            .activeArrangement(tabID: fixture.tabID),
            .activePane(arrangementID: fixture.arrangementID),
            .activeDrawerChild(fixture.drawerCursorKey),
        ]

        // Act
        let participantIDs = items.map(\.participantID)
        let itemIDs = items.map(\.itemID)
        let protocolItemIDs = items.map(\.snapshotItemID)

        // Assert
        #expect(participantIDs == expectedParticipantIDs)
        #expect(itemIDs == expectedItemIDs)
        #expect(protocolItemIDs == expectedItemIDs)
    }

    @Test("each item case retains its correlated raw owner value")
    func eachItemCaseRetainsCorrelatedRawOwnerValue() {
        // Arrange
        let fixture = SnapshotItemFixture()
        let items: [WorkspacePersistenceSnapshotItem] = [
            .workspaceIdentity(fixture.workspaceIdentity),
            .windowMemory(fixture.windowMemory),
            .repository(fixture.repository),
            .worktree(fixture.worktree),
            .watchedPath(fixture.watchedPath),
            .unavailableRepository(fixture.unavailableRepositoryID),
            .paneGraph(fixture.paneGraph),
            .expandedDrawer(fixture.expandedDrawerID),
            .tabShell(fixture.persistedTabShell),
            .activeTab(fixture.activeTabID),
            .tabGraph(fixture.tabGraph),
            .activeArrangement(tabID: fixture.tabID, arrangementID: fixture.activeArrangementID),
            .activePane(arrangementID: fixture.arrangementID, paneID: fixture.activePaneID),
            .activeDrawerChild(key: fixture.drawerCursorKey, childPaneID: fixture.activeDrawerChildID),
        ]

        // Act
        let retainedItems = items

        // Assert
        #expect(retainedItems[0] == .workspaceIdentity(fixture.workspaceIdentity))
        #expect(retainedItems[1] == .windowMemory(fixture.windowMemory))
        #expect(retainedItems[2] == .repository(fixture.repository))
        #expect(retainedItems[3] == .worktree(fixture.worktree))
        #expect(retainedItems[4] == .watchedPath(fixture.watchedPath))
        #expect(retainedItems[5] == .unavailableRepository(fixture.unavailableRepositoryID))
        #expect(retainedItems[6] == .paneGraph(fixture.paneGraph))
        #expect(retainedItems[7] == .expandedDrawer(fixture.expandedDrawerID))
        #expect(retainedItems[8] == .tabShell(fixture.persistedTabShell))
        #expect(retainedItems[9] == .activeTab(fixture.activeTabID))
        #expect(retainedItems[10] == .tabGraph(fixture.tabGraph))
        #expect(
            retainedItems[11]
                == .activeArrangement(tabID: fixture.tabID, arrangementID: fixture.activeArrangementID)
        )
        #expect(
            retainedItems[12]
                == .activePane(arrangementID: fixture.arrangementID, paneID: fixture.activePaneID)
        )
        #expect(
            retainedItems[13]
                == .activeDrawerChild(
                    key: fixture.drawerCursorKey,
                    childPaneID: fixture.activeDrawerChildID
                )
        )
    }
}

private struct SnapshotItemFixture {
    let workspaceIdentity = WorkspacePersistenceSnapshotWorkspaceIdentity(
        workspaceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        workspaceName: "Persistence Fixture",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let windowMemory = WorkspacePersistenceSnapshotWindowMemory(
        sidebarWidth: 312,
        windowFrame: CGRect(x: 10, y: 20, width: 1200, height: 800)
    )
    let repositoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let worktreeID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    let watchedPath = WatchedPath(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        path: URL(filePath: "/tmp/persistence-fixture/watch"),
        addedAt: Date(timeIntervalSince1970: 1_700_000_001)
    )
    let unavailableRepositoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
    let paneGraph = PaneGraphState(
        pane: Pane(
            id: UUID(uuidString: "01900000-0000-7000-8000-000000000006")!,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(title: "Snapshot fixture"),
            kind: .layout(drawer: Drawer())
        )
    )
    let expandedDrawerID = UUID(uuidString: "00000000-0000-0000-0000-000000000007")!
    let tabShell = TabShell(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!,
        name: "Snapshot tab",
        colorHex: "#123456"
    )
    var persistedTabShell: WorkspacePersistenceSnapshotTabShell {
        WorkspacePersistenceSnapshotTabShell(shell: tabShell, sortIndex: 3)
    }
    let activeTabID = UUID(uuidString: "00000000-0000-0000-0000-000000000009")!
    let tabID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    let activeArrangementID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
    let arrangementID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
    let activePaneID = UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
    let drawerCursorKey = ArrangementDrawerCursorKey(
        arrangementId: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
        drawerId: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!
    )
    let activeDrawerChildID = UUID(uuidString: "00000000-0000-0000-0000-000000000016")!

    var worktree: CanonicalWorktree {
        CanonicalWorktree(
            id: worktreeID,
            repoId: repositoryID,
            name: "persistence-fixture",
            path: URL(filePath: "/tmp/persistence-fixture"),
            isMainWorktree: true
        )
    }

    var repository: CanonicalRepo {
        CanonicalRepo(
            id: repositoryID,
            name: "persistence-fixture",
            repoPath: URL(filePath: "/tmp/persistence-fixture"),
            createdAt: Date(timeIntervalSince1970: 1_700_000_002)
        )
    }

    var tabGraph: TabGraphState {
        TabGraphState(tabId: tabID, allPaneIds: [paneGraph.id], arrangements: [])
    }
}
