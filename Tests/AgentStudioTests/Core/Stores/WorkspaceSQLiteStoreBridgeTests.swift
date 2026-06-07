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

    @Test("SQLite flush preserves the live pane graph instead of applying legacy prune-on-save")
    func sqliteFlushPreservesLivePaneGraphWithoutLegacyPruning() throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let identityAtom = WorkspaceIdentityAtom()
        identityAtom.hydrate(
            workspaceId: workspaceId,
            workspaceName: "Live SQLite Workspace",
            createdAt: Date(timeIntervalSince1970: 1_700_000_050)
        )
        let store = WorkspaceStore(
            identityAtom: identityAtom,
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            ),
            sqliteBackend: fixture.backend
        )
        let temporaryPane = store.createPane(
            source: .floating(launchDirectory: nil, title: "Ephemeral"),
            title: "Ephemeral",
            lifetime: .temporary
        )
        let tab = Tab(paneId: temporaryPane.id, name: "Ephemeral Tab")
        store.appendTab(tab)

        #expect(store.flush())

        let paneGraph = try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceId)
        #expect(paneGraph.panes.map(\.id) == [temporaryPane.id])
        let tabShells = try fixture.coreRepository.fetchTabShells(workspaceId: workspaceId)
        #expect(tabShells.map(\.id) == [tab.id])
        let tabGraph = try fixture.coreRepository.fetchTabGraph(workspaceId: workspaceId)
        #expect(tabGraph.tabs.single?.allPaneIds == [temporaryPane.id])
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

    @Test("restore repairs missing active workspace selection before hydrating SQLite")
    func restoreRepairsMissingActiveWorkspaceSelectionBeforeHydratingSQLite() throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_240)
        try fixture.backend.save(
            .init(
                id: workspaceId,
                name: "Missing Selection Workspace",
                createdAt: createdAt,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_245)
            )
        )
        try setRawActiveWorkspaceSelection(nil, in: fixture.coreQueue)

        let loaded = try #require(try fixture.backend.load(preferredWorkspaceId: workspaceId))

        #expect(loaded.id == workspaceId)
        #expect(loaded.name == "Missing Selection Workspace")
        #expect(try fixture.coreRepository.fetchActiveWorkspaceId() == workspaceId)
    }

    @Test("restore prefers caller workspace when active workspace selection is missing")
    func restorePrefersCallerWorkspaceWhenActiveWorkspaceSelectionIsMissing() throws {
        let preferredWorkspaceId = UUID()
        let newerWorkspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: preferredWorkspaceId)
        try fixture.backend.save(
            .init(
                id: preferredWorkspaceId,
                name: "Preferred Workspace",
                createdAt: Date(timeIntervalSince1970: 1_700_000_250),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_260)
            )
        )
        try fixture.backend.save(
            .init(
                id: newerWorkspaceId,
                name: "Newer Fallback Workspace",
                createdAt: Date(timeIntervalSince1970: 1_700_000_270),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_280)
            )
        )
        try setRawActiveWorkspaceSelection(nil, in: fixture.coreQueue)

        let loaded = try #require(try fixture.backend.load(preferredWorkspaceId: preferredWorkspaceId))

        #expect(loaded.id == preferredWorkspaceId)
        #expect(loaded.name == "Preferred Workspace")
        #expect(try fixture.coreRepository.fetchActiveWorkspaceId() == preferredWorkspaceId)
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
        let expectedSourcePath = try #require(persistor.loadLegacyWorkspaceStateFiles().loadedFiles.single?.url.path)
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

    @Test("restore imports every legacy workspace JSON and selects newest modified file")
    func restoreImportsEveryLegacyWorkspaceJSONAndSelectsNewestModifiedFile() throws {
        let olderWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let newerWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: olderWorkspaceId)
        let persistor = WorkspacePersistor(
            workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        #expect(persistor.ensureDirectory())
        try persistor.save(
            .init(
                id: olderWorkspaceId,
                name: "Older Legacy Workspace",
                createdAt: Date(timeIntervalSince1970: 1_700_000_700),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_800)
            )
        )
        try persistor.save(
            .init(
                id: newerWorkspaceId,
                name: "Newest Modified Legacy Workspace",
                createdAt: Date(timeIntervalSince1970: 1_700_000_710),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_720)
            )
        )
        try setModificationDate(
            Date(timeIntervalSince1970: 1_700_000_900),
            for: persistor.canonicalWorkspaceStatePath(for: olderWorkspaceId)
        )
        try setModificationDate(
            Date(timeIntervalSince1970: 1_700_001_000),
            for: persistor.canonicalWorkspaceStatePath(for: newerWorkspaceId)
        )
        let store = WorkspaceStore(persistor: persistor, sqliteBackend: fixture.backend)

        store.restore()

        let workspaces = try fixture.coreRepository.fetchWorkspaces()
        #expect(workspaces.map(\.id) == [olderWorkspaceId, newerWorkspaceId])
        #expect(try fixture.coreRepository.fetchActiveWorkspaceId() == newerWorkspaceId)
        #expect(store.identityAtom.workspaceId == newerWorkspaceId)
        #expect(store.identityAtom.workspaceName == "Newest Modified Legacy Workspace")
        #expect(
            try fixture.coreRepository.fetchLegacyWorkspaceImportStatus(
                workspaceId: olderWorkspaceId
            )?.coreImportedAt != nil
        )
        #expect(
            try fixture.coreRepository.fetchLegacyWorkspaceImportStatus(
                workspaceId: newerWorkspaceId
            )?.coreImportedAt != nil
        )
    }

    @Test("restore breaks legacy active workspace mtime ties by lexicographic id")
    func restoreBreaksLegacyActiveWorkspaceMTimeTiesByLexicographicId() throws {
        let tieWinnerWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let tieLoserWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: tieLoserWorkspaceId)
        let persistor = WorkspacePersistor(
            workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        #expect(persistor.ensureDirectory())
        try persistor.save(
            .init(
                id: tieWinnerWorkspaceId,
                name: "Lexicographic Winner",
                createdAt: Date(timeIntervalSince1970: 1_700_001_100),
                updatedAt: Date(timeIntervalSince1970: 1_700_001_110)
            )
        )
        try persistor.save(
            .init(
                id: tieLoserWorkspaceId,
                name: "Lexicographic Loser",
                createdAt: Date(timeIntervalSince1970: 1_700_001_100),
                updatedAt: Date(timeIntervalSince1970: 1_700_001_120)
            )
        )
        let tiedModificationDate = Date(timeIntervalSince1970: 1_700_001_200)
        try setModificationDate(
            tiedModificationDate,
            for: persistor.canonicalWorkspaceStatePath(for: tieWinnerWorkspaceId)
        )
        try setModificationDate(
            tiedModificationDate,
            for: persistor.canonicalWorkspaceStatePath(for: tieLoserWorkspaceId)
        )
        let store = WorkspaceStore(persistor: persistor, sqliteBackend: fixture.backend)

        store.restore()

        #expect(try fixture.coreRepository.fetchActiveWorkspaceId() == tieWinnerWorkspaceId)
        #expect(store.identityAtom.workspaceId == tieWinnerWorkspaceId)
        #expect(store.identityAtom.workspaceName == "Lexicographic Winner")
    }

    @Test("legacy multi-workspace import does not leave last scanned workspace hydrated when active selection fails")
    func legacyMultiWorkspaceImportDoesNotLeaveLastScannedWorkspaceHydratedWhenActiveSelectionFails() throws {
        let lastScannedWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        let activeWinnerWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000022")!
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: activeWinnerWorkspaceId)
        try failActiveSelection(
            in: fixture.coreQueue,
            from: activeWinnerWorkspaceId,
            to: activeWinnerWorkspaceId
        )
        let persistor = WorkspacePersistor(
            workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        #expect(persistor.ensureDirectory())
        try persistor.save(
            .init(
                id: activeWinnerWorkspaceId,
                name: "Active Winner",
                createdAt: Date(timeIntervalSince1970: 1_700_002_400),
                updatedAt: Date(timeIntervalSince1970: 1_700_002_410)
            )
        )
        try persistor.save(
            .init(
                id: lastScannedWorkspaceId,
                name: "Last Scanned",
                createdAt: Date(timeIntervalSince1970: 1_700_002_400),
                updatedAt: Date(timeIntervalSince1970: 1_700_002_420)
            )
        )
        try setModificationDate(
            Date(timeIntervalSince1970: 1_700_002_500),
            for: persistor.canonicalWorkspaceStatePath(for: activeWinnerWorkspaceId)
        )
        try setModificationDate(
            Date(timeIntervalSince1970: 1_700_002_450),
            for: persistor.canonicalWorkspaceStatePath(for: lastScannedWorkspaceId)
        )
        var recoveryEvents: [PersistenceRecoveryEvent] = []
        let store = WorkspaceStore(
            persistor: persistor,
            sqliteBackend: fixture.backend,
            recoveryReporter: { recoveryEvents.append($0) }
        )

        store.restore()

        #expect(store.identityAtom.workspaceName == "Default Workspace")
        #expect(store.identityAtom.workspaceName != "Last Scanned")
        #expect(recoveryEvents.contains { $0.store == .workspace && $0.recovery == .resetToDefaults })
    }

    @Test("failed legacy import marker does not make incomplete workspace row authoritative")
    func failedLegacyImportMarkerDoesNotMakeIncompleteWorkspaceRowAuthoritative() throws {
        let failedWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000031")!
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.failed.marker.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.failed.marker.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let failingBackend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { _ in
                throw WorkspaceSQLiteBridgeTestError.injectedLocalRepositoryFailure
            }
        )
        let retryBackend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { workspaceId in
                WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
            }
        )
        let persistor = WorkspacePersistor(
            workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        #expect(persistor.ensureDirectory())
        try persistor.save(
            .init(
                id: failedWorkspaceId,
                name: "Retry After Marker",
                createdAt: Date(timeIntervalSince1970: 1_700_002_600),
                updatedAt: Date(timeIntervalSince1970: 1_700_002_700)
            )
        )

        let failedBootStore = WorkspaceStore(persistor: persistor, sqliteBackend: failingBackend)
        failedBootStore.restore()
        #expect(try coreRepository.fetchWorkspace(id: failedWorkspaceId) != nil)
        #expect(try !coreRepository.hasCompletedWorkspaceSQLiteSnapshot(workspaceId: failedWorkspaceId))
        let retryBootStore = WorkspaceStore(persistor: persistor, sqliteBackend: retryBackend)
        retryBootStore.restore()

        #expect(retryBootStore.identityAtom.workspaceId == failedWorkspaceId)
        #expect(retryBootStore.identityAtom.workspaceName == "Retry After Marker")
        #expect(try coreRepository.hasCompletedWorkspaceSQLiteSnapshot(workspaceId: failedWorkspaceId))
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
    let localQueue: DatabaseQueue
    let coreRepository: WorkspaceCoreRepository
    let localRepository: WorkspaceLocalRepository
    let backend: WorkspaceSQLiteStoreBackend
}

private enum WorkspaceSQLiteBridgeTestError: Error {
    case injectedLocalRepositoryFailure
}

@MainActor
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
        localQueue: localQueue,
        coreRepository: coreRepository,
        localRepository: localRepository,
        backend: backend
    )
}

private func setRawActiveWorkspaceSelection(_ value: String?, in databaseQueue: DatabaseQueue) throws {
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

private func setModificationDate(_ date: Date, for path: String) throws {
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path)
}

private func failActiveSelection(
    in databaseQueue: DatabaseQueue,
    from oldWorkspaceId: UUID,
    to newWorkspaceId: UUID
) throws {
    try databaseQueue.write { database in
        try database.execute(
            sql: """
                CREATE TRIGGER fail_active_selection
                BEFORE UPDATE ON app_workspace_selection
                WHEN OLD.active_workspace_id = '\(oldWorkspaceId.uuidString)'
                    AND NEW.active_workspace_id = '\(newWorkspaceId.uuidString)'
                BEGIN
                    SELECT RAISE(ABORT, 'injected active selection failure');
                END
                """
        )
    }
}
