import CoreGraphics
import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteStoreBridgeTests", .serialized)
struct WorkspaceSQLiteStoreBridgeTests {
    @Test("flush writes workspace graph lanes to core and cursor/window lanes to local SQLite")
    func flushWritesSplitWorkspaceLanesToSQLite() throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let identityAtom = WorkspaceIdentityAtom()
        identityAtom.hydrate(
            workspaceId: workspaceId,
            workspaceName: "SQLite Workspace",
            createdAt: createdAt
        )
        let store = WorkspaceStore(
            identityAtom: identityAtom,
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            ),
            sqliteBackend: fixture.backend
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
        store.windowMemoryAtom.setSidebarWidth(321)
        store.windowMemoryAtom.setWindowFrame(CGRect(x: 10, y: 20, width: 900, height: 700))
        let pane = store.createPane(
            source: TerminalSource.worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "SQLite Pane",
            facets: PaneContextFacets(
                repoName: "Derived Repo Name",
                worktreeName: "Derived Worktree Name",
                cwd: worktree.path.appending(path: "Sources"),
                tags: ["swift", "sqlite"]
            )
        )
        var tab = Tab(paneId: pane.id, name: "SQLite Tab")
        let secondArrangement = PaneArrangement(
            name: "Review",
            isDefault: false,
            layout: Layout(paneId: pane.id),
            activePaneId: pane.id
        )
        tab.arrangements.append(secondArrangement)
        store.appendTab(tab)
        store.switchArrangement(to: secondArrangement.id, inTab: tab.id)

        #expect(store.flush())

        let workspace = try #require(try fixture.coreRepository.fetchWorkspace(id: workspaceId))
        #expect(workspace.name == "SQLite Workspace")
        #expect(workspace.createdAt == createdAt)

        let topology = try fixture.coreRepository.fetchRepositoryTopology(workspaceId: workspaceId)
        #expect(topology.repos.map(\.id) == [repo.id])
        #expect(topology.repos.single?.worktrees.map(\.id) == [worktree.id])

        let paneGraph = try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceId)
        let paneRecord = try #require(paneGraph.panes.single)
        #expect(paneRecord.id == pane.id)
        #expect(paneRecord.metadata.title == "SQLite Pane")
        #expect(paneRecord.metadata.durableFacets.tags == ["sqlite", "swift"])

        let shells = try fixture.coreRepository.fetchTabShells(workspaceId: workspaceId)
        #expect(shells == [.init(id: tab.id, name: "SQLite Tab")])
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

    @Test("restore hydrates workspace atoms from active SQLite workspace")
    func restoreHydratesAtomsFromSQLite() throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_100)
        let paneId = UUIDv7.generate()
        let repoId = UUID()
        let worktreeId = UUID()
        let arrangementId = UUID()
        let tabId = UUID()
        let repoPath = URL(filePath: "/tmp/agent-studio-restore-repo")
        let pane = Pane(
            id: paneId,
            content: .terminal(.init(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                paneId: PaneId(uuid: paneId),
                source: .worktree(worktreeId: worktreeId, repoId: repoId, launchDirectory: repoPath),
                createdAt: createdAt,
                title: "Restored SQLite Pane",
                facets: PaneContextFacets(cwd: repoPath.appending(path: "Sources"), tags: ["restore"])
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
            activeArrangementId: arrangementId
        )
        try fixture.backend.save(
            .init(
                id: workspaceId,
                name: "Restored SQLite Workspace",
                repos: [.init(id: repoId, name: "restore-repo", repoPath: repoPath, createdAt: createdAt)],
                worktrees: [
                    .init(
                        id: worktreeId,
                        repoId: repoId,
                        name: "main",
                        path: repoPath,
                        isMainWorktree: true
                    )
                ],
                panes: [pane],
                tabs: [tab],
                activeTabId: tabId,
                sidebarWidth: 444,
                windowFrame: CGRect(x: 1, y: 2, width: 800, height: 600),
                createdAt: createdAt,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_200)
            )
        )

        let restoredStore = WorkspaceStore(
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            ),
            sqliteBackend: fixture.backend
        )

        restoredStore.restore()

        #expect(restoredStore.identityAtom.workspaceId == workspaceId)
        #expect(restoredStore.identityAtom.workspaceName == "Restored SQLite Workspace")
        #expect(restoredStore.windowMemoryAtom.sidebarWidth == 444)
        #expect(restoredStore.windowMemoryAtom.windowFrame == CGRect(x: 1, y: 2, width: 800, height: 600))
        #expect(restoredStore.repositoryTopologyAtom.repos.single?.id == repoId)
        #expect(restoredStore.paneAtom.pane(paneId)?.title == "Restored SQLite Pane")
        #expect(restoredStore.tabLayoutAtom.activeTabId == tabId)
        #expect(restoredStore.tabLayoutAtom.tab(tabId)?.activeArrangementId == arrangementId)
        #expect(!restoredStore.isDirty)
    }

    @Test("restore repairs dangling active workspace selection before hydrating SQLite")
    func restoreRepairsDanglingActiveWorkspaceSelectionBeforeHydratingSQLite() throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_220)
        try fixture.backend.save(
            .init(
                id: workspaceId,
                name: "Repairable SQLite Workspace",
                createdAt: createdAt,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_230)
            )
        )
        let danglingWorkspaceId = UUID()
        try setRawActiveWorkspaceSelection(danglingWorkspaceId.uuidString, in: fixture.coreQueue)

        let loaded = try #require(try fixture.backend.load(preferredWorkspaceId: workspaceId))

        #expect(loaded.id == workspaceId)
        #expect(loaded.name == "Repairable SQLite Workspace")
        #expect(try fixture.coreRepository.fetchActiveWorkspaceId() == workspaceId)
    }

    @Test("failed replacement save preserves the last committed SQLite snapshot")
    func failedReplacementSavePreservesLastCommittedSQLiteSnapshot() throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_250)
        try fixture.backend.save(
            .init(
                id: workspaceId,
                name: "Committed Workspace",
                createdAt: createdAt,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_260)
            )
        )
        let failingBackend = WorkspaceSQLiteStoreBackend(
            coreRepository: fixture.coreRepository,
            makeLocalRepository: { _ in
                throw CocoaError(.fileNoSuchFile)
            }
        )

        #expect(throws: CocoaError.self) {
            try failingBackend.save(
                .init(
                    id: workspaceId,
                    name: "Uncommitted Replacement",
                    createdAt: createdAt,
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_270)
                )
            )
        }

        let loaded = try #require(try fixture.backend.load(preferredWorkspaceId: workspaceId))
        #expect(loaded.name == "Committed Workspace")
        #expect(loaded.name != "Uncommitted Replacement")
    }

    @Test("restore recovers core snapshot when local token advances before failed core replacement")
    func restoreRecoversCoreSnapshotWhenLocalTokenAdvancesBeforeFailedCoreReplacement() throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_280)
        try fixture.backend.save(
            .init(
                id: workspaceId,
                name: "Committed Workspace",
                activeTabId: nil,
                sidebarWidth: 250,
                createdAt: createdAt,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_290)
            )
        )
        let invalidPaneId = UUID()
        let invalidTab = Tab(paneId: invalidPaneId, name: "Invalid Replacement Tab")

        #expect(throws: (any Error).self) {
            try fixture.backend.save(
                .init(
                    id: workspaceId,
                    name: "Invalid Replacement",
                    panes: [],
                    tabs: [invalidTab],
                    activeTabId: invalidTab.id,
                    sidebarWidth: 999,
                    createdAt: createdAt,
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_300)
                )
            )
        }

        let loaded = try #require(try fixture.backend.load(preferredWorkspaceId: workspaceId))
        #expect(loaded.id == workspaceId)
        #expect(loaded.name == "Committed Workspace")
        #expect(loaded.name != "Invalid Replacement")
        #expect(loaded.activeTabId == nil)
        #expect(loaded.sidebarWidth == 250)
    }

    @Test("restore imports legacy workspace JSON into core and local SQLite when rows are missing")
    func restoreImportsLegacyWorkspaceJSONIntoSQLiteWhenRowsAreMissing() throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let persistor = WorkspacePersistor(
            workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        #expect(persistor.ensureDirectory())
        let createdAt = Date(timeIntervalSince1970: 1_700_000_300)
        let pane = Pane(
            content: .terminal(.init(provider: .zmx, lifetime: .persistent)),
            metadata: .init(
                source: .floating(launchDirectory: nil, title: nil),
                createdAt: createdAt,
                title: "Legacy Pane"
            )
        )
        let tab = Tab(paneId: pane.id, name: "Legacy Tab")
        try persistor.save(
            .init(
                id: workspaceId,
                name: "Legacy Workspace",
                panes: [pane],
                tabs: [tab],
                activeTabId: tab.id,
                sidebarWidth: 288,
                windowFrame: CGRect(x: 20, y: 30, width: 1000, height: 700),
                createdAt: createdAt,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_400)
            )
        )
        let store = WorkspaceStore(persistor: persistor, sqliteBackend: fixture.backend)

        store.restore()

        #expect(store.identityAtom.workspaceId == workspaceId)
        #expect(store.identityAtom.workspaceName == "Legacy Workspace")
        #expect(store.paneAtom.pane(pane.id)?.title == "Legacy Pane")
        #expect(store.tabLayoutAtom.activeTabId == tab.id)
        let workspace = try #require(try fixture.coreRepository.fetchWorkspace(id: workspaceId))
        #expect(workspace.name == "Legacy Workspace")
        let paneGraph = try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceId)
        #expect(paneGraph.panes.map(\.id) == [pane.id])
        let shells = try fixture.coreRepository.fetchTabShells(workspaceId: workspaceId)
        #expect(shells == [.init(id: tab.id, name: "Legacy Tab")])
        let windowState = try #require(try fixture.localRepository.fetchWindowState())
        #expect(windowState.sidebarWidth == 288)
        #expect(windowState.windowFrame == CGRect(x: 20, y: 30, width: 1000, height: 700))
        let cursorState = try fixture.localRepository.fetchCursorState()
        #expect(cursorState.activeTabId == tab.id)
        let importStatus = try #require(
            try fixture.coreRepository.fetchLegacyWorkspaceImportStatus(workspaceId: workspaceId))
        let expectedSourcePath = persistor.workspacesDir
            .appending(path: "\(workspaceId.uuidString).workspace.state.json")
            .path
        #expect(importStatus.sourceStatePath == expectedSourcePath)
        #expect(importStatus.coreImportedAt != nil)
        try fixture.backend.markLegacyWorkspaceArchived(
            workspaceId: workspaceId,
            archivedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
        let archivedStatus = try #require(
            try fixture.coreRepository.fetchLegacyWorkspaceImportStatus(workspaceId: workspaceId)
        )
        #expect(archivedStatus.archivedAt == Date(timeIntervalSince1970: 1_700_000_500))
    }

    @Test("restore does not replay stale legacy JSON when SQLite restore fails")
    func restoreDoesNotReplayStaleLegacyJSONWhenSQLiteRestoreFails() throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let persistor = WorkspacePersistor(
            workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        #expect(persistor.ensureDirectory())
        let createdAt = Date(timeIntervalSince1970: 1_700_000_500)
        try fixture.backend.save(
            .init(
                id: workspaceId,
                name: "SQLite Authoritative Workspace",
                createdAt: createdAt,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_600)
            )
        )
        try persistor.save(
            .init(
                id: workspaceId,
                name: "Stale Legacy Workspace",
                createdAt: createdAt,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
        )
        try fixture.coreQueue.write { database in
            try database.execute(sql: "DROP TABLE pane")
        }
        var recoveryEvents: [PersistenceRecoveryEvent] = []
        let store = WorkspaceStore(
            persistor: persistor,
            sqliteBackend: fixture.backend,
            recoveryReporter: { event in recoveryEvents.append(event) }
        )

        store.restore()

        #expect(store.identityAtom.workspaceName == "Default Workspace")
        #expect(store.identityAtom.workspaceName != "Stale Legacy Workspace")
        #expect(recoveryEvents.contains { $0.store == .workspace && $0.recovery == .resetToDefaults })
    }

    @Test("restore does not treat incomplete SQLite workspace rows as authoritative")
    func restoreDoesNotTreatIncompleteSQLiteWorkspaceRowsAsAuthoritative() throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let persistor = WorkspacePersistor(
            workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        #expect(persistor.ensureDirectory())
        let createdAt = Date(timeIntervalSince1970: 1_700_000_700)
        try fixture.coreRepository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Partial SQLite Workspace",
                createdAt: createdAt,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_800)
            )
        )
        try fixture.coreRepository.selectActiveWorkspace(
            workspaceId,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_800)
        )
        try persistor.save(
            .init(
                id: workspaceId,
                name: "Stale Legacy Workspace",
                createdAt: createdAt,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
        )
        var recoveryEvents: [PersistenceRecoveryEvent] = []
        let store = WorkspaceStore(
            persistor: persistor,
            sqliteBackend: fixture.backend,
            recoveryReporter: { event in recoveryEvents.append(event) }
        )

        store.restore()

        #expect(store.identityAtom.workspaceName == "Default Workspace")
        #expect(store.identityAtom.workspaceName != "Partial SQLite Workspace")
        #expect(store.identityAtom.workspaceName != "Stale Legacy Workspace")
        #expect(recoveryEvents.contains { $0.store == .workspace && $0.recovery == .resetToDefaults })
    }
}

private struct WorkspaceSQLiteBridgeFixture {
    let coreQueue: DatabaseQueue
    let coreRepository: WorkspaceCoreRepository
    let localRepository: WorkspaceLocalRepository
    let backend: WorkspaceSQLiteStoreBackend
}

private func makeWorkspaceSQLiteBridgeFixture(workspaceId: UUID) throws -> WorkspaceSQLiteBridgeFixture {
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
        coreQueue: coreQueue,
        coreRepository: coreRepository,
        localRepository: localRepository,
        backend: backend
    )
}

private func setRawActiveWorkspaceSelection(_ value: String, in databaseQueue: DatabaseQueue) throws {
    try databaseQueue.writeWithoutTransaction { database in
        try database.execute(sql: "PRAGMA foreign_keys = OFF")
        try database.execute(
            sql: """
                UPDATE app_workspace_selection
                SET active_workspace_id = ?
                WHERE singleton_id = 1
                """,
            arguments: [value]
        )
        try database.execute(sql: "PRAGMA foreign_keys = ON")
    }
}
