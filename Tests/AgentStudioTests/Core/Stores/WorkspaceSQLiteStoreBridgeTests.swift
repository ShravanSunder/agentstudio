import CoreGraphics
import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteStoreBridgeTests", .serialized)
struct WorkspaceSQLiteStoreBridgeTests {
    @Test("SQLite composition defaults missing local window state")
    func sqliteCompositionDefaultsMissingWindowState() throws {
        var snapshot = try makeStrictWorkspaceSQLiteStateBridgeSnapshot()
        snapshot.windowState = nil

        let composition = try WorkspaceSQLiteStateBridge.workspaceSnapshot(from: snapshot)

        #expect(composition.sidebarWidth == 250)
        #expect(composition.windowFrame == nil)
    }

    @Test("SQLite materialization rejects missing required drawer expansion state")
    func sqliteMaterializationRejectsMissingDrawerExpansionState() throws {
        var snapshot = try makeStrictWorkspaceSQLiteStateBridgeSnapshot()
        snapshot.cursorState.drawerExpansionByDrawerId = [:]

        #expect(throws: WorkspaceSQLiteStateBridgeError.missingDrawerExpansionState) {
            try WorkspaceSQLiteStateBridge.workspaceSnapshot(from: snapshot)
        }
    }

    @Test("SQLite materialization rejects missing required active arrangement state")
    func sqliteMaterializationRejectsMissingActiveArrangementState() throws {
        var snapshot = try makeStrictWorkspaceSQLiteStateBridgeSnapshot()
        snapshot.cursorState.activeArrangementIdsByTabId = [:]

        #expect(throws: WorkspaceSQLiteStateBridgeError.missingActiveArrangementState) {
            try WorkspaceSQLiteStateBridge.workspaceSnapshot(from: snapshot)
        }
    }

    @Test("SQLite materialization rejects missing required tab shell")
    func sqliteMaterializationRejectsMissingTabShell() throws {
        var snapshot = try makeStrictWorkspaceSQLiteStateBridgeSnapshot()
        snapshot.tabShells = []

        #expect(throws: WorkspaceSQLiteStateBridgeError.missingTabShell) {
            try WorkspaceSQLiteStateBridge.workspaceSnapshot(from: snapshot)
        }
    }

    @Test("SQLite materialization preserves exact durable pane metadata")
    func sqliteMaterializationPreservesExactDurablePaneMetadata() throws {
        let launchDirectory = URL(filePath: "/tmp/strict-launch")
        var snapshot = try makeStrictWorkspaceSQLiteStateBridgeSnapshot()
        var paneRecord = try #require(snapshot.paneGraph.panes.single)
        paneRecord.metadata.launchDirectory = launchDirectory
        paneRecord.metadata.note = "  exact note with surrounding whitespace  \n"
        paneRecord.metadata.checkoutRef = "  refs/heads/noncanonical  "
        paneRecord.metadata.durableFacets.cwd = nil
        snapshot.paneGraph.panes = [paneRecord]

        let state = try WorkspaceSQLiteStateBridge.workspaceSnapshot(from: snapshot)
        let pane = try #require(state.panes.single)

        #expect(pane.metadata.note == "  exact note with surrounding whitespace  \n")
        #expect(pane.metadata.checkoutRef == "  refs/heads/noncanonical  ")
        #expect(pane.metadata.launchDirectory == launchDirectory)
        #expect(pane.metadata.cwd == nil)
    }

    @Test("SQLite materialization rejects a layout pane without its persisted drawer")
    func sqliteMaterializationRejectsLayoutPaneWithoutPersistedDrawer() throws {
        let workspaceId = UUIDv7.generate()
        let paneId = UUIDv7.generate()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = WorkspaceSQLiteStateBridge.Snapshot(
            workspace: .init(
                id: workspaceId,
                name: "Missing drawer",
                createdAt: timestamp,
                updatedAt: timestamp
            ),
            paneGraph: .init(
                panes: [
                    .init(
                        id: paneId,
                        content: .terminal(
                            provider: .zmx,
                            lifetime: .persistent,
                            zmxSessionID: .generateUUIDv7()
                        ),
                        metadata: .init(
                            executionBackend: .local,
                            createdAt: timestamp,
                            title: "Persisted layout pane"
                        ),
                        residency: .active,
                        placement: .layout,
                        drawer: nil,
                        updatedAt: timestamp
                    )
                ]
            ),
            tabShells: [],
            tabGraph: .init(tabs: []),
            cursorState: .init(
                activeTabId: nil,
                activeArrangementIdsByTabId: [:],
                activePaneIdsByArrangementId: [:],
                drawerExpansionByDrawerId: [:],
                activeChildIdsByArrangementDrawer: [:]
            ),
            windowState: .init(sidebarWidth: 250, windowFrame: nil)
        )

        #expect(throws: WorkspaceSQLiteStateBridgeError.layoutPaneMissingDrawer(paneId)) {
            try WorkspaceSQLiteStateBridge.workspaceSnapshot(from: snapshot)
        }
    }

    @Test("flush writes composition lanes without replacing global topology")
    func flushWritesCompositionWithoutReplacingGlobalTopology() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let identityAtom = WorkspaceIdentityAtom(workspaceId: UUIDv7.generate())
        identityAtom.replaceIdentity(
            workspaceId: workspaceId,
            workspaceName: "SQLite Workspace",
            createdAt: createdAt
        )
        let store = WorkspaceStore(
            identityAtom: identityAtom,
            sqliteDatastore: workspaceSQLiteDatastore(from: fixture.backend)
        )

        let repo = store.addRepo(at: URL(filePath: "/tmp/agent-studio-sqlite-repo"))
        let discoveredWorktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/agent-studio-sqlite-repo"),
            isMainWorktree: true
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [discoveredWorktree])
        let worktree = try #require(store.repositoryTopologyAtom.repo(repo.id)?.worktrees.single)
        let expectedTopology = WorkspaceCoreRepository.RepositoryTopologyRecord(
            watchedPaths: [],
            repos: [
                .init(
                    id: repo.id,
                    name: repo.name,
                    repoPath: repo.repoPath,
                    createdAt: repo.createdAt,
                    isFavorite: repo.isFavorite,
                    note: repo.note,
                    worktrees: [
                        .init(
                            id: worktree.id,
                            repoId: worktree.repoId,
                            name: worktree.name,
                            path: worktree.path,
                            isMainWorktree: worktree.isMainWorktree,
                            note: worktree.note
                        )
                    ],
                    tags: repo.tags
                )
            ],
            unavailableRepoIds: []
        )
        try fixture.coreRepository.replaceRepositoryTopology(expectedTopology)
        let persistedTopologyBeforeFlush = try fixture.coreRepository.fetchRepositoryTopology()
        store.windowMemoryAtom.setSidebarWidth(321)
        store.windowMemoryAtom.setWindowFrame(CGRect(x: 10, y: 20, width: 900, height: 700))
        let pane = store.createPane(
            launchDirectory: worktree.path,
            title: "SQLite Pane",
            zmxSessionID: .generateUUIDv7(),
            facets: PaneContextFacets(
                repoId: repo.id,
                repoName: "Derived Repo Name",
                worktreeId: worktree.id,
                worktreeName: "Derived Worktree Name",
                cwd: worktree.path.appending(path: "Sources")
            )
        )
        var tab = Tab(paneId: pane.id, name: "SQLite Tab")
        tab.colorHex = "#22CC88"
        let secondArrangement = PaneArrangement(
            name: "Review",
            isDefault: false,
            layout: Layout(paneId: pane.id),
            activePaneId: pane.id
        )
        tab.arrangements.append(secondArrangement)
        store.appendTab(tab)
        store.switchArrangement(to: secondArrangement.id, inTab: tab.id)

        #expect((await store.flushAsync()).succeeded)

        let workspace = try #require(try fixture.coreRepository.fetchWorkspace(id: workspaceId))
        #expect(workspace.name == "SQLite Workspace")
        #expect(workspace.createdAt == createdAt)

        let topology = try fixture.coreRepository.fetchRepositoryTopology()
        #expect(topology == persistedTopologyBeforeFlush)

        let paneGraph = try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceId)
        let paneRecord = try #require(paneGraph.panes.single)
        #expect(paneRecord.id == pane.id)
        #expect(paneRecord.metadata.title == "SQLite Pane")

        let shells = try fixture.coreRepository.fetchTabShells(workspaceId: workspaceId)
        #expect(shells == [.init(id: tab.id, name: "SQLite Tab", colorHex: "#22CC88")])
        let tabGraph = try fixture.coreRepository.fetchTabGraph(workspaceId: workspaceId)
        let tabState = try #require(tabGraph.tabs.single)
        #expect(tabState.tabId == tab.id)
        #expect(tabState.allPaneIds == [pane.id])
        #expect(tabState.arrangements.map(\.id).contains(secondArrangement.id))

        let windowState = try #require(try fixture.localRepository.fetchWindowState())
        #expect(windowState.sidebarWidth == 321)
        #expect(windowState.windowFrame == CGRect(x: 10, y: 20, width: 900, height: 700))

        let cursorState = try fixture.localRepository.fetchCursorState()
        #expect(cursorState.activeTabId == tab.id)
        #expect(cursorState.activeArrangementIdsByTabId[tab.id] == secondArrangement.id)
        #expect(cursorState.activePaneIdsByArrangementId[secondArrangement.id] == pane.id)
    }

    @Test("SQLite flush preserves the live pane graph instead of applying legacy prune-on-save")
    func sqliteFlushPreservesLivePaneGraphWithoutLegacyPruning() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let identityAtom = WorkspaceIdentityAtom(workspaceId: UUIDv7.generate())
        identityAtom.replaceIdentity(
            workspaceId: workspaceId,
            workspaceName: "Live SQLite Workspace",
            createdAt: Date(timeIntervalSince1970: 1_700_000_050)
        )
        let store = WorkspaceStore(
            identityAtom: identityAtom,
            sqliteDatastore: workspaceSQLiteDatastore(from: fixture.backend)
        )
        let temporaryPane = store.createPane(
            title: "Ephemeral",
            lifetime: .temporary,
            zmxSessionID: .generateUUIDv7()
        )
        let tab = Tab(paneId: temporaryPane.id, name: "Ephemeral Tab")
        store.appendTab(tab)

        #expect((await store.flushAsync()).succeeded)

        let paneGraph = try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceId)
        #expect(paneGraph.panes.map(\.id) == [temporaryPane.id])
        let tabShells = try fixture.coreRepository.fetchTabShells(workspaceId: workspaceId)
        #expect(tabShells.map(\.id) == [tab.id])
        let tabGraph = try fixture.coreRepository.fetchTabGraph(workspaceId: workspaceId)
        #expect(tabGraph.tabs.single?.allPaneIds == [temporaryPane.id])
    }

    @Test("restore hydrates canonical composition from active SQLite workspace")
    func restoreHydratesCanonicalCompositionFromSQLite() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_100)
        let paneId = UUIDv7.generate()
        let repoId = UUID()
        let worktreeId = UUID()
        let arrangementId = UUID()
        let tabId = UUID()
        let repoPath = URL(filePath: "/tmp/agent-studio-restore-repo")
        let storedZmxSessionText = "existing-opaque-zmx-session-id"
        let storedZmxSessionID = try #require(ZmxSessionID(restoring: storedZmxSessionText))
        let pane = Pane(
            id: paneId,
            content: .terminal(
                .init(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: storedZmxSessionID
                )
            ),
            metadata: PaneMetadata(
                paneId: PaneId(existingUUID: paneId),
                launchDirectory: repoPath,
                createdAt: createdAt,
                title: "Restored SQLite Pane",
                facets: PaneContextFacets(
                    repoId: repoId,
                    worktreeId: worktreeId,
                    cwd: repoPath.appending(path: "Sources")
                )
            )
        )
        let arrangement = PaneArrangement(
            id: arrangementId,
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneId),
            activePaneId: paneId
        )
        let tab = Tab(
            id: tabId,
            name: "Restored Tab",
            allPaneIds: [paneId],
            arrangements: [arrangement],
            activeArrangementId: arrangementId,
            colorHex: "#33AA99"
        )
        let workspaceSnapshot = WorkspaceSQLiteSnapshot(
            id: workspaceId,
            name: "Restored SQLite Workspace",
            panes: [pane],
            tabs: [tab],
            activeTabId: tabId,
            sidebarWidth: 444,
            windowFrame: CGRect(x: 1, y: 2, width: 800, height: 600),
            createdAt: createdAt,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        try fixture.coreRepository.replaceRepositoryTopology(
            .init(
                watchedPaths: [],
                repos: [
                    .init(
                        id: repoId,
                        name: "restore-repo",
                        repoPath: repoPath,
                        createdAt: createdAt,
                        worktrees: [
                            .init(
                                id: worktreeId,
                                repoId: repoId,
                                name: "main",
                                path: repoPath,
                                isMainWorktree: true
                            )
                        ]
                    )
                ],
                unavailableRepoIds: []
            )
        )
        try fixture.backend.save(
            WorkspaceSQLiteSaveBundle(workspace: workspaceSnapshot)
        )

        let restoredStore = restoredWorkspaceStore(from: fixture.backend)

        await restoredStore.loadCanonicalComposition()

        #expect(restoredStore.identityAtom.workspaceId == workspaceId)
        #expect(restoredStore.identityAtom.workspaceName == "Restored SQLite Workspace")
        #expect(restoredStore.windowMemoryAtom.sidebarWidth == 444)
        #expect(restoredStore.tabLayoutAtom.tabs.single?.colorHex == "#33AA99")
        #expect(restoredStore.windowMemoryAtom.windowFrame == CGRect(x: 1, y: 2, width: 800, height: 600))
        #expect(restoredStore.paneAtom.pane(paneId)?.title == "Restored SQLite Pane")
        #expect(
            restoredStore.paneAtom.pane(paneId)?.terminalState?.zmxSessionID.rawValue
                == storedZmxSessionText
        )
        #expect(restoredStore.tabLayoutAtom.activeTabId == tabId)
        #expect(restoredStore.tabLayoutAtom.tab(tabId)?.activeArrangementId == arrangementId)
        #expect(!restoredStore.isDirty)
    }

    private func restoredWorkspaceStore(from backend: WorkspaceSQLiteStoreBackend) -> WorkspaceStore {
        let datastore = workspaceSQLiteDatastore(from: backend)
        let atomRegistry = AtomRegistry()
        let saveCoordinator = WorkspaceSQLiteSaveCoordinator(
            identityAtom: atomRegistry.workspaceIdentity,
            windowMemoryAtom: atomRegistry.workspaceWindowMemory,
            workspacePaneAtom: atomRegistry.workspacePane,
            workspaceTabLayoutAtom: atomRegistry.workspaceTabLayout,
            sqliteDatastore: datastore
        )
        return WorkspaceStore(
            identityAtom: atomRegistry.workspaceIdentity,
            windowMemoryAtom: atomRegistry.workspaceWindowMemory,
            repositoryTopologyAtom: atomRegistry.workspaceRepositoryTopology,
            paneAtom: atomRegistry.workspacePane,
            tabLayoutAtom: atomRegistry.workspaceTabLayout,
            mutationCoordinator: atomRegistry.workspaceMutationCoordinator,
            sqliteDatastore: datastore,
            sqliteSaveCoordinator: saveCoordinator
        )
    }
}

private func makeStrictWorkspaceSQLiteStateBridgeSnapshot() throws -> WorkspaceSQLiteStateBridge.Snapshot {
    let workspaceId = UUIDv7.generate()
    let paneId = UUIDv7.generate()
    let drawerId = UUIDv7.generate()
    let arrangementId = UUIDv7.generate()
    let tabId = UUIDv7.generate()
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let pane = Pane(
        id: paneId,
        content: .terminal(
            .init(
                provider: .zmx,
                lifetime: .persistent,
                zmxSessionID: .generateUUIDv7()
            )
        ),
        metadata: PaneMetadata(
            paneId: PaneId(existingUUID: paneId),
            createdAt: timestamp,
            title: "Strict pane"
        ),
        kind: .layout(
            drawer: Drawer(
                drawerId: drawerId,
                parentPaneId: paneId,
                isExpanded: true
            )
        )
    )
    let arrangement = PaneArrangement(
        id: arrangementId,
        name: "Default",
        isDefault: true,
        layout: Layout(paneId: paneId),
        activePaneId: paneId
    )
    let tab = Tab(
        id: tabId,
        name: "Strict tab",
        allPaneIds: [paneId],
        arrangements: [arrangement],
        activeArrangementId: arrangementId
    )
    let liveSnapshot = WorkspaceSQLiteSnapshot(
        id: workspaceId,
        name: "Strict workspace",
        panes: [pane],
        tabs: [tab],
        activeTabId: tabId,
        sidebarWidth: 321,
        windowFrame: CGRect(x: 1, y: 2, width: 800, height: 600),
        createdAt: timestamp,
        updatedAt: timestamp
    )
    return WorkspaceSQLiteStateBridge.Snapshot(
        workspace: WorkspaceSQLiteStateBridge.workspaceRecord(from: liveSnapshot),
        paneGraph: try WorkspaceSQLiteStateBridge.paneGraphRecord(from: liveSnapshot),
        tabShells: WorkspaceSQLiteStateBridge.tabShellRecords(from: liveSnapshot),
        tabGraph: WorkspaceSQLiteStateBridge.tabGraphRecord(from: liveSnapshot),
        cursorState: WorkspaceSQLiteStateBridge.cursorStateRecord(from: liveSnapshot),
        windowState: WorkspaceSQLiteStateBridge.windowStateRecord(from: liveSnapshot)
    )
}

struct WorkspaceSQLiteBridgeFixture {
    let localQueue: DatabaseQueue
    let coreRepository: WorkspaceCoreRepository
    let localRepository: WorkspaceLocalRepository
    let backend: WorkspaceSQLiteStoreBackend
}

@MainActor
func makeWorkspaceSQLiteBridgeFixture(workspaceId: UUID) throws -> WorkspaceSQLiteBridgeFixture {
    let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.bridge.core")
    let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.bridge.local")
    try WorkspaceCoreMigrations.migrate(coreQueue)
    try WorkspaceLocalMigrations.migrate(localQueue)
    let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
    let localRepository = WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
    let backend = WorkspaceSQLiteStoreBackend(
        coreRepository: coreRepository,
        makeLocalRepository: { workspaceId in
            WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
        }
    )
    return .init(
        localQueue: localQueue,
        coreRepository: coreRepository,
        localRepository: localRepository,
        backend: backend
    )
}
