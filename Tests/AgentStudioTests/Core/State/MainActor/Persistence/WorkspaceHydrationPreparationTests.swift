import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceHydrationPreparationTests {
    @Test
    func validLegacyPreparationMatchesTransformerHydrationSemantics() throws {
        let repoID = UUID()
        let validWorktreeID = UUID()
        let invalidWorktreeID = UUID()
        let validPane = makePane(title: "Valid", worktreeID: validWorktreeID)
        let invalidPane = makePane(title: "Invalid", worktreeID: invalidWorktreeID)
        let invalidArrangement = PaneArrangement(
            name: "Missing worktree",
            isDefault: true,
            layout: Layout(paneId: invalidPane.id),
            activePaneId: invalidPane.id
        )
        let validArrangement = PaneArrangement(
            name: "Valid",
            isDefault: false,
            layout: Layout(paneId: validPane.id),
            activePaneId: validPane.id
        )
        let tab = Tab(
            name: "Restored",
            allPaneIds: [invalidPane.id, validPane.id],
            arrangements: [invalidArrangement, validArrangement],
            activeArrangementId: validArrangement.id
        )
        let state = WorkspacePersistor.PersistableState(
            id: UUID(),
            name: "Prepared workspace",
            repos: [
                CanonicalRepo(
                    id: repoID,
                    name: "agent-studio",
                    repoPath: URL(filePath: "/tmp/agent-studio")
                )
            ],
            worktrees: [
                CanonicalWorktree(
                    id: validWorktreeID,
                    repoId: repoID,
                    name: "main",
                    path: URL(filePath: "/tmp/agent-studio"),
                    isMainWorktree: true
                )
            ],
            unavailableRepoIds: [repoID],
            panes: [validPane, invalidPane],
            tabs: [tab],
            activeTabId: tab.id,
            sidebarWidth: 312,
            windowFrame: CGRect(x: 10, y: 20, width: 900, height: 700),
            watchedPaths: [WatchedPath(path: URL(filePath: "/tmp"))],
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let preparation = WorkspaceHydrationPreparation.prepare(.legacy(state))
        let prepared = try #require(preparation.preparedValue)

        let identityAtom = WorkspaceIdentityAtom()
        let windowMemoryAtom = WorkspaceWindowMemoryAtom()
        let topologyAtom = RepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayoutAtom = WorkspaceTabLayoutAtom()
        let repairReport = WorkspacePersistenceTransformer.hydrate(
            state,
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: topologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom
        )

        #expect(prepared.identity.workspaceId == identityAtom.workspaceId)
        #expect(prepared.identity.workspaceName == identityAtom.workspaceName)
        #expect(prepared.identity.createdAt == identityAtom.createdAt)
        #expect(prepared.windowMemory.sidebarWidth == windowMemoryAtom.sidebarWidth)
        #expect(prepared.windowMemory.windowFrame == windowMemoryAtom.windowFrame)
        #expect(prepared.runtimeRepos == topologyAtom.repos)
        #expect(prepared.watchedPaths == topologyAtom.watchedPaths)
        #expect(prepared.unavailableRepoIds == topologyAtom.unavailableRepoIds)
        #expect(Set(prepared.panes) == Set(paneAtom.liveSQLitePanes.values))
        #expect(prepared.panes.map(\.id) == [validPane.id])
        #expect(prepared.tabs == tabLayoutAtom.tabs)
        #expect(prepared.activeTabId == tabLayoutAtom.activeTabId)
        #expect(prepared.repairReport == repairReport)
        #expect(prepared.validWorktreeIds == [validWorktreeID])
        #expect(
            prepared.drawerParentPaneIdByDrawerId
                == WorkspacePersistenceTransformer.drawerParentPaneIdsByDrawerId(
                    from: paneAtom.liveSQLitePanes.values
                )
        )
    }

    @Test
    func sqliteWorkspaceIdentityMismatchRejectsBeforePreparation() {
        let workspaceID = UUID()
        let topologyID = UUID()
        let result = WorkspaceHydrationPreparation.prepare(
            .sqlite(
                workspace: WorkspaceSQLiteSnapshot(id: workspaceID),
                repositoryTopology: RepositoryTopologySQLiteSnapshot(
                    id: topologyID,
                    updatedAt: Date(timeIntervalSince1970: 1)
                )
            )
        )

        #expect(
            result
                == .rejected(
                    .sqliteWorkspaceIDMismatch(
                        workspaceID: workspaceID,
                        repositoryTopologyID: topologyID
                    )
                )
        )
    }

    @Test
    func duplicateRepositoryIdentityPreservesTopologyRejection() {
        let repositoryID = UUID()
        let repository = CanonicalRepo(
            id: repositoryID,
            name: "duplicate",
            repoPath: URL(filePath: "/tmp/duplicate")
        )
        let state = WorkspacePersistor.PersistableState(repos: [repository, repository])

        #expect(
            WorkspaceHydrationPreparation.prepare(.legacy(state))
                == .rejected(.repositoryTopology(.duplicateRepositoryID(repositoryID)))
        )
    }

    @Test
    func duplicatePaneIdentityRejects() {
        let pane = makePane(title: "Duplicate")
        let result = WorkspaceHydrationPreparation.prepare(
            .legacy(WorkspacePersistor.PersistableState(panes: [pane, pane]))
        )

        #expect(result == .rejected(.duplicatePaneID(pane.id)))
    }

    @Test
    func duplicateDrawerIdentityRejects() {
        let drawerID = UUID()
        let firstPane = makePane(title: "First", drawerID: drawerID)
        let secondPane = makePane(title: "Second", drawerID: drawerID)
        let result = WorkspaceHydrationPreparation.prepare(
            .legacy(WorkspacePersistor.PersistableState(panes: [firstPane, secondPane]))
        )

        #expect(result == .rejected(.duplicateDrawerID(drawerID)))
    }

    @Test
    func duplicateTabIdentityRejects() {
        let pane = makePane(title: "Tab pane")
        let tab = Tab(paneId: pane.id)
        let result = WorkspaceHydrationPreparation.prepare(
            .legacy(WorkspacePersistor.PersistableState(panes: [pane], tabs: [tab, tab]))
        )

        #expect(result == .rejected(.duplicateTabID(tab.id)))
    }

    @Test
    func duplicateArrangementIdentityRejectsAcrossTabs() {
        let firstPane = makePane(title: "First")
        let secondPane = makePane(title: "Second")
        let arrangementID = UUID()
        let firstArrangement = PaneArrangement(
            id: arrangementID,
            layout: Layout(paneId: firstPane.id),
            activePaneId: firstPane.id
        )
        let secondArrangement = PaneArrangement(
            id: arrangementID,
            layout: Layout(paneId: secondPane.id),
            activePaneId: secondPane.id
        )
        let firstTab = Tab(
            allPaneIds: [firstPane.id],
            arrangements: [firstArrangement],
            activeArrangementId: arrangementID
        )
        let secondTab = Tab(
            allPaneIds: [secondPane.id],
            arrangements: [secondArrangement],
            activeArrangementId: arrangementID
        )
        let result = WorkspaceHydrationPreparation.prepare(
            .legacy(
                WorkspacePersistor.PersistableState(
                    panes: [firstPane, secondPane],
                    tabs: [firstTab, secondTab]
                )
            )
        )

        #expect(result == .rejected(.duplicateArrangementID(arrangementID)))
    }

    @Test
    func drawerMembershipFollowsParentLayoutOrderInsteadOfDrawerUUIDOrder() throws {
        let firstDrawerID = try #require(UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff"))
        let secondDrawerID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        var firstParent = makePane(
            title: "First parent",
            drawerID: firstDrawerID
        )
        var secondParent = makePane(
            title: "Second parent",
            drawerID: secondDrawerID
        )
        let firstDrawerChild = makeDrawerChildPane(title: "First child", parentPaneID: firstParent.id)
        let secondDrawerChild = makeDrawerChildPane(title: "Second child", parentPaneID: secondParent.id)
        firstParent.withDrawer { $0.paneIds = [firstDrawerChild.id] }
        secondParent.withDrawer { $0.paneIds = [secondDrawerChild.id] }
        let arrangement = PaneArrangement(
            layout: Layout.autoTiled([firstParent.id, secondParent.id]),
            activePaneId: firstParent.id,
            drawerViews: [
                firstDrawerID: DrawerView(
                    layout: DrawerGridLayout(topRow: Layout(paneId: firstDrawerChild.id))
                ),
                secondDrawerID: DrawerView(
                    layout: DrawerGridLayout(topRow: Layout(paneId: secondDrawerChild.id))
                ),
            ]
        )
        let tab = Tab(
            allPaneIds: [],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )

        let result = WorkspaceHydrationPreparation.prepare(
            .legacy(
                WorkspacePersistor.PersistableState(
                    panes: [firstParent, secondParent, firstDrawerChild, secondDrawerChild],
                    tabs: [tab]
                )
            )
        )

        let prepared = try #require(result.preparedValue)
        #expect(
            prepared.tabs[0].allPaneIds
                == [firstParent.id, secondParent.id, firstDrawerChild.id, secondDrawerChild.id]
        )
    }

    @Test
    func preparationDoesNotMutateSuppliedHydrationOwners() {
        let originalWorkspaceID = UUID()
        let originalPane = makePane(title: "Original")
        let originalTab = Tab(paneId: originalPane.id)
        let identityAtom = WorkspaceIdentityAtom()
        let windowMemoryAtom = WorkspaceWindowMemoryAtom()
        let topologyAtom = RepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayoutAtom = WorkspaceTabLayoutAtom()
        identityAtom.hydrate(
            workspaceId: originalWorkspaceID,
            workspaceName: "Original workspace",
            createdAt: Date(timeIntervalSince1970: 10)
        )
        windowMemoryAtom.hydrate(sidebarWidth: 444, windowFrame: nil)
        paneAtom.hydrate(persistedPanes: [originalPane], validWorktreeIds: [])
        tabLayoutAtom.hydrate(
            persistedTabs: [originalTab],
            activeTabId: originalTab.id,
            validPaneIds: [originalPane.id]
        )

        _ = WorkspaceHydrationPreparation.prepare(
            .legacy(
                WorkspacePersistor.PersistableState(
                    id: UUID(),
                    name: "Candidate",
                    panes: [makePane(title: "Candidate")]
                )
            )
        )

        #expect(identityAtom.workspaceId == originalWorkspaceID)
        #expect(identityAtom.workspaceName == "Original workspace")
        #expect(windowMemoryAtom.sidebarWidth == 444)
        #expect(topologyAtom.repos.isEmpty)
        #expect(paneAtom.pane(originalPane.id) != nil)
        #expect(tabLayoutAtom.tabs == [originalTab])
        #expect(tabLayoutAtom.activeTabId == originalTab.id)
    }

    @Test
    func preparationCanRunOffMainActor() async throws {
        let pane = makePane(title: "Detached")
        let source = WorkspaceHydrationSource.legacy(
            WorkspacePersistor.PersistableState(panes: [pane], tabs: [Tab(paneId: pane.id)])
        )

        // Detached execution is required here to prove preparation is not main-actor isolated.
        // swiftlint:disable:next no_task_detached
        let result = await Task.detached {
            WorkspaceHydrationPreparation.prepare(source)
        }.value

        let prepared = try #require(result.preparedValue)
        #expect(prepared.panes.map(\.id) == [pane.id])
    }

    private func makePane(
        title: String,
        worktreeID: UUID? = nil,
        drawerID: UUID = UUID()
    ) -> Pane {
        let paneID = UUIDv7.generate()
        return Pane(
            id: paneID,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                launchDirectory: URL(filePath: "/tmp/\(title)"),
                title: title,
                facets: PaneContextFacets(
                    worktreeId: worktreeID,
                    cwd: URL(filePath: "/tmp/\(title)")
                )
            ),
            kind: .layout(
                drawer: Drawer(
                    drawerId: drawerID,
                    parentPaneId: paneID,
                    paneIds: []
                )
            )
        )
    }

    private func makeDrawerChildPane(title: String, parentPaneID: UUID) -> Pane {
        Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                launchDirectory: URL(filePath: "/tmp/\(title)"),
                title: title,
                facets: PaneContextFacets(cwd: URL(filePath: "/tmp/\(title)"))
            ),
            kind: .drawerChild(parentPaneId: parentPaneID)
        )
    }
}

extension WorkspaceHydrationPreparationResult {
    fileprivate var preparedValue: PreparedWorkspaceHydration? {
        guard case .prepared(let prepared) = self else { return nil }
        return prepared
    }
}
