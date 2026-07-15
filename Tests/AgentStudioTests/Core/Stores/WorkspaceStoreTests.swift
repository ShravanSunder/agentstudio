import Foundation
// swiftlint:disable file_length type_body_length
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class WorkspaceStoreTests {

    private var store: WorkspaceStore!
    private var tempDir: URL!

    init() {
        // Use a temp directory to avoid polluting real workspace data
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "workspace-store-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: persistor)
        store.restore()
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
        store = nil
    }

    // MARK: - Init & Restore

    @Test

    func test_restore_emptyState() {
        // Assert
        #expect(store.panes.isEmpty)
        #expect(store.repos.isEmpty)
        #expect(store.tabs.isEmpty)
        #expect((store.activeTabId) == nil)
    }

    @Test
    func test_restore_loadedState_doesNotMarkDirtyOrScheduleDebouncedSave() async throws {
        let persistedDir = FileManager.default.temporaryDirectory
            .appending(path: "workspace-store-restore-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: persistedDir)
        #expect(persistor.ensureDirectory())

        let workspaceId = UUID()
        let pane = Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                title: "Restored"
            )
        )
        let tab = Tab(paneId: pane.id)
        try persistor.save(
            .init(
                id: workspaceId,
                panes: [pane],
                tabs: [tab],
                activeTabId: tab.id
            )
        )

        let clock = TestPushClock()
        let restoredStore = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: persistor,
            persistDebounceDuration: .milliseconds(1),
            clock: clock
        )

        restoredStore.restore()
        await Task.yield()

        #expect(!restoredStore.isDirty)
        #expect(clock.pendingSleepCount == 0)
    }

    @Test
    func test_restore_corruptWorkspace_reportsRecovery() throws {
        let persistedDir = FileManager.default.temporaryDirectory
            .appending(path: "workspace-store-corrupt-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: persistedDir)
        #expect(persistor.ensureDirectory())
        let workspaceId = UUID()
        let stateURL = persistedDir.appending(path: "\(workspaceId.uuidString).workspace.state.json")
        let cacheURL = persistedDir.appending(path: "\(workspaceId.uuidString).workspace.cache.json")
        let uiURL = persistedDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        let sidebarCacheURL = persistedDir.appending(path: "\(workspaceId.uuidString).workspace.sidebar-cache.json")
        let inboxURL = persistedDir.appending(path: "\(workspaceId.uuidString).notification-inbox.json")
        try Data("not-json".utf8).write(to: stateURL, options: .atomic)
        try Data("{}".utf8).write(to: cacheURL, options: .atomic)
        try Data("{}".utf8).write(to: uiURL, options: .atomic)
        try Data("{}".utf8).write(to: sidebarCacheURL, options: .atomic)
        try Data("{}".utf8).write(to: inboxURL, options: .atomic)
        var reportedRecovery: PersistenceRecoveryEvent?
        let restoredStore = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: persistor,
            recoveryReporter: { reportedRecovery = $0 }
        )

        restoredStore.restore()

        #expect(reportedRecovery?.store == .workspace)
        #expect(reportedRecovery?.workspaceId == workspaceId)
        #expect(reportedRecovery?.recovery == .quarantinedAndReset)
        #expect(reportedRecovery?.quarantinedFilename?.contains(".workspace.state.corrupt-") == true)
        #expect(reportedRecovery?.quarantinedFilename?.contains(".workspace.cache.corrupt-") == true)
        #expect(reportedRecovery?.quarantinedFilename?.contains(".workspace.ui.corrupt-") == true)
        #expect(reportedRecovery?.quarantinedFilename?.contains(".workspace.sidebar-cache.corrupt-") == true)
        #expect(reportedRecovery?.quarantinedFilename?.contains(".notification-inbox.corrupt-") == true)
        #expect(!FileManager.default.fileExists(atPath: stateURL.path))
        #expect(!FileManager.default.fileExists(atPath: cacheURL.path))
        #expect(!FileManager.default.fileExists(atPath: uiURL.path))
        #expect(!FileManager.default.fileExists(atPath: sidebarCacheURL.path))
        #expect(!FileManager.default.fileExists(atPath: inboxURL.path))
        #expect(restoredStore.panes.isEmpty)
    }

    @Test
    func archiveLegacyWorkspaceFiles_movesCompanionFilesIntoLegacyImportedDirectory() throws {
        let persistedDir = FileManager.default.temporaryDirectory
            .appending(path: "workspace-store-archive-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: persistedDir)
        #expect(persistor.ensureDirectory())
        let workspaceId = UUID()
        let legacyURLs = [
            persistedDir.appending(path: "\(workspaceId.uuidString).workspace.state.json"),
            persistedDir.appending(path: "\(workspaceId.uuidString).workspace.cache.json"),
            persistedDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json"),
            persistedDir.appending(path: "\(workspaceId.uuidString).workspace.sidebar-cache.json"),
            persistedDir.appending(path: "\(workspaceId.uuidString).notification-inbox.json"),
        ]
        for url in legacyURLs {
            try Data(url.lastPathComponent.utf8).write(to: url, options: .atomic)
        }

        let result = try #require(persistor.archiveLegacyWorkspaceFiles(for: workspaceId))

        #expect(result.failedFilenames.isEmpty)
        #expect(Set(result.archivedFilenames) == Set(legacyURLs.map(\.lastPathComponent)))
        let archiveDirectory =
            persistedDir
            .appending(path: "legacy-imported")
            .appending(path: result.archiveDirectoryName)
        #expect(FileManager.default.fileExists(atPath: archiveDirectory.path))
        for url in legacyURLs {
            #expect(!FileManager.default.fileExists(atPath: url.path))
            #expect(
                FileManager.default.fileExists(atPath: archiveDirectory.appending(path: url.lastPathComponent).path))
        }
    }

    @Test
    func hasLegacyWorkspaceFilesReportsWhetherAnyLegacyFileExists() throws {
        let persistedDir = FileManager.default.temporaryDirectory
            .appending(path: "workspace-store-legacy-file-presence-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: persistedDir)
        #expect(persistor.ensureDirectory())
        let workspaceId = UUID()

        #expect(!persistor.hasLegacyWorkspaceFiles(for: workspaceId))

        let stateURL = persistedDir.appending(path: "\(workspaceId.uuidString).workspace.state.json")
        try Data("state".utf8).write(to: stateURL, options: .atomic)

        #expect(persistor.hasLegacyWorkspaceFiles(for: workspaceId))
    }

    @Test
    func archiveLegacyWorkspaceFilesReportsPriorIncompleteArchiveDirectory() throws {
        let persistedDir = FileManager.default.temporaryDirectory
            .appending(path: "workspace-store-incomplete-archive-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: persistedDir)
        #expect(persistor.ensureDirectory())
        let workspaceId = UUID()
        let stateURL = persistedDir.appending(path: "\(workspaceId.uuidString).workspace.state.json")
        try Data("state".utf8).write(to: stateURL, options: .atomic)
        let incompleteDirectoryName = "2026-06-06T00-00-00Z"
        let incompleteDirectory =
            persistedDir
            .appending(path: "legacy-imported")
            .appending(path: incompleteDirectoryName)
        try FileManager.default.createDirectory(at: incompleteDirectory, withIntermediateDirectories: true)
        try Data("partial".utf8).write(
            to: incompleteDirectory.appending(path: "\(workspaceId.uuidString).workspace.cache.json"),
            options: .atomic
        )
        try Data("incomplete".utf8).write(
            to: incompleteDirectory.appending(path: ".archive-incomplete-\(workspaceId.uuidString).marker"),
            options: .atomic
        )

        let result = try #require(persistor.archiveLegacyWorkspaceFiles(for: workspaceId))

        #expect(result.archivedFilenames.isEmpty)
        #expect(result.failedFilenames == [stateURL.lastPathComponent])
        #expect(result.incompleteArchiveDirectoryNames == [incompleteDirectoryName])
        #expect(!result.succeeded)
        #expect(FileManager.default.fileExists(atPath: stateURL.path))
    }

    @Test
    func test_flushFailure_reportsSaveFailedRecovery() {
        let blockedDirectoryURL = FileManager.default.temporaryDirectory
            .appending(path: "workspace-store-blocked-\(UUID().uuidString)")
        try? Data("not-a-directory".utf8).write(to: blockedDirectoryURL, options: .atomic)
        var reportedRecovery: PersistenceRecoveryEvent?
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: WorkspacePersistor(workspacesDir: blockedDirectoryURL),
            recoveryReporter: { reportedRecovery = $0 }
        )

        #expect(store.flush() == false)
        #expect(reportedRecovery?.store == .workspace)
        #expect(reportedRecovery?.workspaceId == store.identityAtom.workspaceId)
        #expect(reportedRecovery?.recovery == .saveFailed)
    }

    @Test
    func test_workspaceStore_readsAndPersistsTheProvidedLiveAtomScope() throws {
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let atoms = AtomRegistry()
        let scopedStore = WorkspaceStore(
            workspacePersistenceRevisionOwner: atoms.workspacePersistenceRevisionOwner,
            catalogAtom: atoms.workspaceRepositoryTopology,
            graphAtom: atoms.workspacePane,
            interactionAtom: atoms.workspaceTabLayout,
            persistor: persistor
        )

        let pane = Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                title: "Scoped"
            )
        )
        atoms.workspacePane.addPane(pane)

        #expect(scopedStore.graphAtom === atoms.workspacePane)
        #expect(scopedStore.pane(pane.id)?.title == "Scoped")

        #expect(scopedStore.flush())

        let restoredStore = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: persistor)
        restoredStore.restore()
        #expect(restoredStore.pane(pane.id)?.title == "Scoped")
    }

    @Test
    func test_workspaceStore_exposesResolvedTabWriteOwners() {
        let tabCursorAtom = WorkspaceTabCursorAtom()
        let tabShellAtom = WorkspaceTabShellAtom(cursorAtom: tabCursorAtom)
        let tabGraphAtom = WorkspaceTabGraphAtom()
        let arrangementCursorAtom = WorkspaceArrangementCursorAtom()
        let panePresentationAtom = WorkspacePanePresentationAtom()
        let tabArrangementAtom = WorkspaceTabArrangementAtom(
            graphAtom: tabGraphAtom,
            cursorAtom: arrangementCursorAtom,
            presentationAtom: panePresentationAtom
        )
        let tabLayoutAtom = WorkspaceTabLayoutAtom(
            shellAtom: tabShellAtom,
            arrangementAtom: tabArrangementAtom
        )

        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            tabLayoutAtom: tabLayoutAtom,
            persistor: WorkspacePersistor(workspacesDir: tempDir)
        )

        #expect(store.tabShellAtom === tabShellAtom)
        #expect(store.tabCursorAtom === tabCursorAtom)
        #expect(store.tabArrangementAtom === tabArrangementAtom)
        #expect(store.tabGraphAtom === tabGraphAtom)
        #expect(store.arrangementCursorAtom === arrangementCursorAtom)
        #expect(store.panePresentationAtom === panePresentationAtom)
    }

    // MARK: - Pane CRUD

    @Test

    func test_createPane_addsToPanes() {
        // Act
        let pane = store.createPane()

        // Assert
        #expect(store.panes.count == 1)
        #expect((store.pane(pane.id)) != nil)
        #expect(store.pane(pane.id)?.provider == .zmx)
    }

    @Test

    func test_createPane_worktreeSource() {
        // Arrange
        let worktreeId = UUID()
        let repoId = UUID()
        let launchDirectory = URL(fileURLWithPath: "/tmp/worktree")

        // Act
        let pane = store.createPane(
            launchDirectory: launchDirectory,
            title: "Feature",
            facets: PaneContextFacets(repoId: repoId, worktreeId: worktreeId, cwd: launchDirectory)
        )

        // Assert
        #expect(pane.worktreeId == worktreeId)
        #expect(pane.repoId == repoId)
        #expect(pane.title == "Feature")
    }

    @Test
    func updatePaneLiveLocation_resolvesKnownWorktreeAndPreservesLaunchSource() {
        let repo = store.addRepo(at: URL(filePath: "/tmp/live-identity-repo"))
        let main = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/live-identity-repo"),
            isMainWorktree: true
        )
        let feature = Worktree(
            repoId: repo.id,
            name: "feature",
            path: URL(filePath: "/tmp/live-identity-repo-feature")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [main, feature])

        let pane = store.createPane(
            launchDirectory: main.path,
            title: "Terminal",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: main.id, cwd: main.path)
        )

        let cwd = feature.path.appending(path: "Sources")
        let result = store.paneAtom.updatePaneCWDAndResolvedContext(
            pane.id,
            cwd: cwd,
            resolvedContext: store.repositoryTopologyAtom.repoAndWorktree(containing: cwd)
        )
        #expect(result == .applied)

        let updated = store.pane(pane.id)
        #expect(updated?.metadata.cwd == cwd)
        #expect(updated?.repoId == repo.id)
        #expect(updated?.worktreeId == feature.id)
        #expect(updated?.metadata.repoName == repo.name)
        #expect(updated?.metadata.worktreeName == "feature")

        #expect(updated?.metadata.launchDirectory == main.path)
    }

    @Test
    func updatePaneLiveLocation_clearsLiveRepoAndWorktreeWhenCwdLeavesKnownWorktrees() throws {
        let repo = store.addRepo(at: URL(filePath: "/tmp/live-clear-repo"))
        let main = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/live-clear-repo"),
            isMainWorktree: true
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [main])
        let storedWorktree = try #require(store.repos.first { $0.id == repo.id }?.worktrees.first)
        let pane = store.createPane(
            launchDirectory: storedWorktree.path,
            title: "Terminal",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: storedWorktree.id, cwd: storedWorktree.path)
        )
        store.appendTab(Tab(paneId: pane.id))

        let externalCwd = URL(filePath: "/tmp/outside-known-worktrees")
        let result = store.paneAtom.updatePaneCWDAndResolvedContext(
            pane.id,
            cwd: externalCwd,
            resolvedContext: store.repositoryTopologyAtom.repoAndWorktree(containing: externalCwd)
        )
        #expect(result == .applied)

        let updated = store.pane(pane.id)
        #expect(updated?.metadata.cwd == externalCwd)
        #expect(updated?.repoId == nil)
        #expect(updated?.worktreeId == nil)
        #expect(updated?.metadata.repoName == nil)
        #expect(updated?.metadata.worktreeName == nil)

        #expect(store.flush())
        let restoredStore = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: WorkspacePersistor(workspacesDir: tempDir))
        restoredStore.restore()
        let restoredPane = try #require(restoredStore.pane(pane.id))
        #expect(restoredPane.metadata.cwd == externalCwd)
        #expect(restoredPane.repoId == nil)
        #expect(restoredPane.worktreeId == nil)

        #expect(updated?.metadata.launchDirectory == storedWorktree.path)
    }

    @Test
    func updatePaneLiveLocation_preservesLaunchDirectoryWhileLiveFacetsFollowKnownCwd() {
        let repo = store.addRepo(at: URL(filePath: "/tmp/live-floating-repo"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "floating-target",
            path: URL(filePath: "/tmp/live-floating-repo/floating-target")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        let pane = store.createPane(
            launchDirectory: URL(filePath: "/tmp/scratch"),
            title: "Scratch Terminal"
        )

        let changed = store.paneAtom.updatePaneCWDAndResolvedContext(
            pane.id,
            cwd: worktree.path,
            resolvedContext: store.repositoryTopologyAtom.repoAndWorktree(containing: worktree.path)
        )

        let updated = store.pane(pane.id)
        #expect(changed == .applied)
        #expect(updated?.repoId == repo.id)
        #expect(updated?.worktreeId == worktree.id)
        #expect(updated?.metadata.launchDirectory == URL(filePath: "/tmp/scratch"))
    }

    @Test
    func updatePaneLiveLocation_isIdempotentWhenCwdAndResolvedContextAreUnchanged() {
        let repo = store.addRepo(at: URL(filePath: "/tmp/live-idempotent-repo"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/live-idempotent-repo"),
            isMainWorktree: true
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        let pane = store.createPane(
            launchDirectory: worktree.path,
            title: "Terminal",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path),
        )
        let resolvedContext = store.repositoryTopologyAtom.repoAndWorktree(containing: worktree.path)

        let first = store.paneAtom.updatePaneCWDAndResolvedContext(
            pane.id,
            cwd: worktree.path,
            resolvedContext: resolvedContext
        )
        let second = store.paneAtom.updatePaneCWDAndResolvedContext(
            pane.id,
            cwd: worktree.path,
            resolvedContext: resolvedContext
        )

        #expect(first == .applied)
        #expect(second == .unchanged)
    }

    @Test
    func updatePaneLiveLocation_reportsMissingPaneSeparately() {
        let result = store.paneAtom.updatePaneCWDAndResolvedContext(
            UUID(),
            cwd: URL(filePath: "/tmp/missing-pane"),
            resolvedContext: nil
        )

        #expect(result == .paneMissing)
    }

    @Test("workspace pane atom updates pane note")
    func workspacePaneAtomUpdatesPaneNote() {
        let atom = WorkspacePaneAtom()
        let pane = Pane(
            id: PaneId().uuid,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata()
        )
        #expect(atom.insertRestoredPane(pane))

        atom.updatePaneNote(pane.id, note: "  Restart backend after deploy  ")

        #expect(atom.pane(pane.id)?.metadata.note == "Restart backend after deploy")
    }

    @Test

    func test_removePane_removesFromPanes() {
        // Arrange
        let pane = store.createPane()

        // Act
        store.removePane(pane.id)

        // Assert
        #expect(store.panes.isEmpty)
    }

    @Test

    func test_removePane_removesFromLayouts() {
        // Arrange
        let p1 = store.createPane()
        let p2 = store.createPane()
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)

        // Act
        store.removePane(p1.id)

        // Assert — removePane cascades to layouts and removes empty tabs
        #expect(store.tabs.count == 1)
        #expect(store.tabs[0].paneIds == [p2.id])
        #expect(store.tabs[0].activePaneId == p2.id)
    }

    @Test

    func test_removePane_lastInTab_closesTab() {
        // Arrange
        let pane = store.createPane()
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        #expect(store.tabs.count == 1)

        // Act
        store.removePane(pane.id)

        // Assert
        #expect(store.tabs.isEmpty)
    }

    @Test

    func test_updatePaneTitle() {
        // Arrange
        let pane = store.createPane()

        // Act
        store.updatePaneTitle(pane.id, title: "New Title")

        // Assert
        #expect(store.pane(pane.id)?.title == "New Title")
    }

    @Test

    func test_updatePaneCWD_updatesValue() {
        // Arrange
        let pane = store.createPane()
        let cwd = URL(fileURLWithPath: "/tmp/workspace")

        // Act
        store.updatePaneCWD(pane.id, cwd: cwd)

        // Assert
        #expect(store.pane(pane.id)?.metadata.cwd == cwd)
    }

    @Test

    func test_updatePaneCWD_nilClearsValue() {
        // Arrange
        let pane = store.createPane()
        store.updatePaneCWD(pane.id, cwd: URL(fileURLWithPath: "/tmp"))

        // Act
        store.updatePaneCWD(pane.id, cwd: nil)

        // Assert
        #expect((store.pane(pane.id)?.metadata.cwd) == nil)
    }

    @Test

    func test_updatePaneCWD_sameCWD_noOpDoesNotMarkDirty() {
        // Arrange
        let pane = store.createPane()
        let cwd = URL(fileURLWithPath: "/tmp")
        store.updatePaneCWD(pane.id, cwd: cwd)
        store.flush()

        // Act — update with same CWD
        store.updatePaneCWD(pane.id, cwd: cwd)

        // Assert — should not be dirty (dedup guard)
        #expect(!(store.isDirty))
    }

    @Test

    func test_updatePaneCWD_unknownPane_doesNotCrash() {
        // Act — should just log warning, not crash
        store.updatePaneCWD(UUID(), cwd: URL(fileURLWithPath: "/tmp"))

        // Assert — no crash, panes unchanged
        #expect(store.panes.isEmpty)
    }

    @Test

    func test_setResidency() {
        // Arrange
        let pane = store.createPane()
        #expect(pane.residency == .active)

        // Act
        let expiresAt = Date(timeIntervalSinceNow: 300)
        store.setResidency(.pendingUndo(expiresAt: expiresAt), for: pane.id)

        // Assert
        #expect(store.pane(pane.id)?.residency == .pendingUndo(expiresAt: expiresAt))
    }

    @Test

    func test_setResidency_backgrounded() {
        // Arrange
        let pane = store.createPane()

        // Act
        store.setResidency(.backgrounded, for: pane.id)

        // Assert
        #expect(store.pane(pane.id)?.residency == .backgrounded)
    }

    @Test

    func test_createPane_withLifetimeAndResidency() {
        // Act
        let pane = store.createPane(
            lifetime: .temporary,
            residency: .backgrounded
        )

        // Assert
        #expect(pane.lifetime == .temporary)
        #expect(pane.residency == .backgrounded)
    }

    // MARK: - Derived State

    @Test

    func test_isWorktreeActive_noPanes_returnsFalse() {
        #expect(!(store.isWorktreeActive(UUID())))
    }

    @Test

    func test_isWorktreeActive_withPane_returnsTrue() {
        // Arrange
        let worktreeId = UUID()
        store.createPane(
            launchDirectory: URL(fileURLWithPath: "/tmp/worktree"),
            facets: PaneContextFacets(
                repoId: UUID(),
                worktreeId: worktreeId,
                cwd: URL(fileURLWithPath: "/tmp/worktree")
            )
        )

        // Assert
        #expect(store.isWorktreeActive(worktreeId))
    }

    @Test

    func test_paneCount_forWorktree() {
        // Arrange
        let worktreeId = UUID()
        let repoId = UUID()
        store.createPane(
            launchDirectory: URL(fileURLWithPath: "/tmp/worktree"),
            facets: PaneContextFacets(
                repoId: repoId, worktreeId: worktreeId, cwd: URL(fileURLWithPath: "/tmp/worktree"))
        )
        store.createPane(
            launchDirectory: URL(fileURLWithPath: "/tmp/worktree"),
            facets: PaneContextFacets(
                repoId: repoId, worktreeId: worktreeId, cwd: URL(fileURLWithPath: "/tmp/worktree"))
        )
        store.createPane(
            launchDirectory: URL(fileURLWithPath: "/tmp/worktree"),
            facets: PaneContextFacets(
                repoId: UUID(),
                worktreeId: UUID(),
                cwd: URL(fileURLWithPath: "/tmp/worktree")
            )
        )

        // Assert
        #expect(store.paneCount(for: worktreeId) == 2)
    }

    // MARK: - Tab Mutations

    @Test

    func test_appendTab_addsToTabs() {
        // Arrange
        let pane = store.createPane()
        let tab = Tab(paneId: pane.id)

        // Act
        store.appendTab(tab)

        // Assert
        #expect(store.tabs.count == 1)
        #expect(store.activeTabId == tab.id)
    }

    @Test

    func test_removeTab_removesAndUpdatesActiveTabId() {
        // Arrange
        let s1 = store.createPane()
        let s2 = store.createPane()
        let tab1 = Tab(paneId: s1.id)
        let tab2 = Tab(paneId: s2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)
        store.setActiveTab(tab1.id)

        // Act
        store.removeTab(tab1.id)

        // Assert
        #expect(store.tabs.count == 1)
        #expect(store.activeTabId == tab2.id)
    }

    @Test

    func test_insertTab_atIndex() {
        // Arrange
        let s1 = store.createPane()
        let s2 = store.createPane()
        let s3 = store.createPane()
        let tab1 = Tab(paneId: s1.id)
        let tab2 = Tab(paneId: s2.id)
        let tab3 = Tab(paneId: s3.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Act
        store.insertTab(tab3, at: 1)

        // Assert
        #expect(store.tabs.count == 3)
        #expect(store.tabs[1].id == tab3.id)
    }

    @Test

    func test_moveTab() {
        // Arrange
        let s1 = store.createPane()
        let s2 = store.createPane()
        let s3 = store.createPane()
        let tab1 = Tab(paneId: s1.id)
        let tab2 = Tab(paneId: s2.id)
        let tab3 = Tab(paneId: s3.id)
        store.appendTab(tab1)
        store.appendTab(tab2)
        store.appendTab(tab3)

        // Act — move tab3 to position 0
        store.moveTab(fromId: tab3.id, toIndex: 0)

        // Assert
        #expect(store.tabs[0].id == tab3.id)
        #expect(store.tabs[1].id == tab1.id)
        #expect(store.tabs[2].id == tab2.id)
    }

    // MARK: - Layout Mutations

    @Test

    func test_insertPane_splitsLayout() {
        // Arrange
        let s1 = store.createPane()
        let s2 = store.createPane()
        let tab = Tab(paneId: s1.id)
        store.appendTab(tab)

        // Act
        store.insertPane(
            s2.id, inTab: tab.id, at: s1.id,
            direction: .horizontal, position: .after, sizingMode: .halveTarget
        )

        // Assert
        let updatedTab = store.tabs[0]
        #expect(updatedTab.isSplit)
        #expect(updatedTab.paneIds == [s1.id, s2.id])
    }

    @Test

    func test_removePaneFromLayout_collapsesToSingle() {
        // Arrange
        let s1 = store.createPane()
        let s2 = store.createPane()
        let tab = makeTab(paneIds: [s1.id, s2.id])
        store.appendTab(tab)

        // Act
        store.removePaneFromLayout(s1.id, inTab: tab.id)

        // Assert
        let updatedTab = store.tabs[0]
        #expect(!(updatedTab.isSplit))
        #expect(updatedTab.paneIds == [s2.id])
        #expect(updatedTab.activePaneId == s2.id)
    }

    @Test

    func test_removePaneFromLayout_lastPane_removesTab() {
        // Arrange
        let s1 = store.createPane()
        let tab = Tab(paneId: s1.id)
        store.appendTab(tab)

        // Act
        store.removePaneFromLayout(s1.id, inTab: tab.id)

        // Assert
        #expect(store.tab(tab.id) == nil)
    }

    @Test

    func test_equalizePanes() {
        // Arrange
        let s1 = store.createPane()
        let s2 = store.createPane()
        let tab = Tab(paneId: s1.id)
        store.appendTab(tab)
        store.insertPane(
            s2.id, inTab: tab.id, at: s1.id, direction: .horizontal, position: .after, sizingMode: .halveTarget)

        guard let dividerId = store.tabs[0].layout.dividerIds.first else {
            Issue.record("Expected divider")
            return
        }
        store.resizePane(tabId: tab.id, splitId: dividerId, ratio: 0.3)

        // Act
        store.equalizePanes(tabId: tab.id)

        // Assert
        #expect(abs((store.tabs[0].layout.ratioForSplit(dividerId) ?? 0.0) - (0.5)) <= 0.001)
    }

    // MARK: - Compound Operations

    @Test

    func test_breakUpTab_splitIntoIndividual() {
        // Arrange
        let s1 = store.createPane()
        let s2 = store.createPane()
        let s3 = store.createPane()
        let tab = makeTab(paneIds: [s1.id, s2.id, s3.id])
        store.appendTab(tab)

        // Act
        let newTabs = store.breakUpTab(tab.id)

        // Assert
        #expect(newTabs.count == 3)
        #expect(store.tabs.count == 3)
        #expect(store.tabs[0].paneIds == [s1.id])
        #expect(store.tabs[1].paneIds == [s2.id])
        #expect(store.tabs[2].paneIds == [s3.id])
    }

    @Test

    func test_breakUpTab_singlePane_noOp() {
        // Arrange
        let s1 = store.createPane()
        let tab = Tab(paneId: s1.id)
        store.appendTab(tab)

        // Act
        let newTabs = store.breakUpTab(tab.id)

        // Assert
        #expect(newTabs.isEmpty)
        #expect(store.tabs.count == 1)
    }

    @Test

    func test_extractPane() {
        // Arrange
        let s1 = store.createPane()
        let s2 = store.createPane()
        let tab = makeTab(paneIds: [s1.id, s2.id])
        store.appendTab(tab)

        // Act
        let newTab = store.extractPane(s2.id, fromTab: tab.id)

        // Assert
        #expect((newTab) != nil)
        #expect(store.tabs.count == 2)
        #expect(store.tabs[0].paneIds == [s1.id])
        #expect(store.tabs[1].paneIds == [s2.id])
        #expect(store.activeTabId == newTab?.id)
    }

    @Test
    func test_extractPane_removesPaneFromSourceArrangementMinimizedSet() {
        let s1 = store.createPane()
        let s2 = store.createPane()
        let tab = makeTab(paneIds: [s1.id, s2.id])
        store.appendTab(tab)
        _ = store.minimizePane(s2.id, inTab: tab.id)

        _ = store.extractPane(s2.id, fromTab: tab.id)

        #expect(store.tabs[0].activeMinimizedPaneIds.isEmpty)
    }

    @Test

    func test_extractPane_singlePane_noOp() {
        // Arrange
        let s1 = store.createPane()
        let tab = Tab(paneId: s1.id)
        store.appendTab(tab)

        // Act
        let result = store.extractPane(s1.id, fromTab: tab.id)

        // Assert
        #expect((result) == nil)
        #expect(store.tabs.count == 1)
    }

    @Test

    func test_mergeTab() {
        // Arrange
        let s1 = store.createPane()
        let s2 = store.createPane()
        let tab1 = Tab(paneId: s1.id)
        let tab2 = Tab(paneId: s2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Act — merge tab2 into tab1
        store.mergeTab(
            sourceId: tab2.id, intoTarget: tab1.id,
            at: s1.id, direction: .horizontal, position: .after
        )

        // Assert
        #expect(store.tabs.count == 1)
        #expect(store.tabs[0].paneIds.count == 2)
        #expect(store.tabs[0].paneIds.contains(s1.id))
        #expect(store.tabs[0].paneIds.contains(s2.id))
    }

    @Test
    func test_mergeTab_sameSourceAndTarget_noOp() {
        let pane = store.createPane()
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        store.mergeTab(
            sourceId: tab.id,
            intoTarget: tab.id,
            at: pane.id,
            direction: .horizontal,
            position: .after
        )

        #expect(store.tabs.count == 1)
        #expect(store.tabs[0].id == tab.id)
        #expect(store.tabs[0].paneIds == [pane.id])
    }

    // MARK: - Queries

    @Test

    func test_pane_byId() {
        // Arrange
        let pane = store.createPane()

        // Assert
        #expect(store.pane(pane.id)?.id == pane.id)
        #expect((store.pane(UUID())) == nil)
    }

    @Test

    func test_tabContaining_paneId() {
        // Arrange
        let pane = store.createPane()
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        // Assert
        #expect(store.tabContaining(paneId: pane.id)?.id == tab.id)
        #expect((store.tabContaining(paneId: UUID())) == nil)
    }

    @Test

    func test_panes_forWorktree() {
        // Arrange
        let worktreeId = UUID()
        let repoId = UUID()
        store.createPane(
            launchDirectory: URL(fileURLWithPath: "/tmp/worktree"),
            facets: PaneContextFacets(
                repoId: repoId, worktreeId: worktreeId, cwd: URL(fileURLWithPath: "/tmp/worktree"))
        )
        store.createPane(
            launchDirectory: URL(fileURLWithPath: "/tmp/worktree"),
            facets: PaneContextFacets(
                repoId: repoId, worktreeId: worktreeId, cwd: URL(fileURLWithPath: "/tmp/worktree"))
        )
        store.createPane(
            launchDirectory: URL(fileURLWithPath: "/tmp/worktree"),
            facets: PaneContextFacets(
                repoId: UUID(),
                worktreeId: UUID(),
                cwd: URL(fileURLWithPath: "/tmp/worktree")
            )
        )

        // Assert
        #expect(store.panes(for: worktreeId).count == 2)
    }

    // MARK: - Persistence Round-Trip

    @Test

    func test_persistence_saveAndRestore() {
        // Arrange
        let pane = store.createPane(
            title: "Persistent"
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.flush()

        // Act — create new store with same persistor
        let persistor2 = WorkspacePersistor(workspacesDir: tempDir)
        let store2 = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: persistor2)
        store2.restore()

        // Assert
        #expect(store2.panes.count == 1)
        // Find the pane by the known ID
        #expect(store2.pane(pane.id)?.title == "Persistent")
        #expect(store2.tabs.count == 1)
        #expect(store2.tabs[0].paneIds.count == 1)
    }

    @Test

    func test_persistence_temporaryPanesExcluded() {
        // Arrange
        let persistent = store.createPane(
            title: "Persistent",
            lifetime: .persistent
        )
        store.createPane(
            title: "Temporary",
            lifetime: .temporary
        )
        let tab = Tab(paneId: persistent.id)
        store.appendTab(tab)
        store.flush()

        // Act — restore from disk
        let persistor2 = WorkspacePersistor(workspacesDir: tempDir)
        let store2 = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: persistor2)
        store2.restore()

        // Assert — only persistent pane restored
        #expect(store2.panes.count == 1)
        #expect(store2.pane(persistent.id)?.title == "Persistent")
        #expect(store2.pane(persistent.id)?.lifetime == .persistent)
    }

    // MARK: - Persistence Pruning

    @Test

    func test_persistence_temporaryPanesPrunedFromLayouts() {
        // Arrange — create a tab with both persistent and temporary panes in a split layout
        let persistent = store.createPane(
            title: "Persistent",
            lifetime: .persistent
        )
        let temporary = store.createPane(
            title: "Temporary",
            lifetime: .temporary
        )
        let tab = makeTab(paneIds: [persistent.id, temporary.id])
        store.appendTab(tab)
        store.flush()

        // Act — restore from disk
        let persistor2 = WorkspacePersistor(workspacesDir: tempDir)
        let store2 = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: persistor2)
        store2.restore()

        // Assert — only persistent pane remains, no dangling temporary IDs in layouts
        #expect(store2.panes.count == 1)
        #expect((store2.pane(persistent.id)) != nil)
        #expect(store2.tabs.count == 1)
        #expect(store2.tabs[0].paneIds == [persistent.id])
        #expect(!(store2.tabs[0].isSplit))
    }

    @Test

    func test_persistence_allTemporary_tabPruned() {
        // Arrange — tab with only temporary panes
        let temp1 = store.createPane(
            lifetime: .temporary
        )
        let tab = Tab(paneId: temp1.id)
        store.appendTab(tab)
        store.flush()

        // Act
        let persistor2 = WorkspacePersistor(workspacesDir: tempDir)
        let store2 = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: persistor2)
        store2.restore()

        // Assert — tab fully pruned since all panes were temporary
        #expect(store2.panes.isEmpty)
        #expect(store2.tabs.isEmpty)
    }

    @Test

    func test_persistence_activeTabIdFixupAfterPrune() {
        // Arrange — two tabs: one all-temporary (active), one persistent
        let persistent = store.createPane(
            lifetime: .persistent
        )
        let temporary = store.createPane(
            lifetime: .temporary
        )
        let tab1 = Tab(paneId: persistent.id)
        let tab2 = Tab(paneId: temporary.id)
        store.appendTab(tab1)
        store.appendTab(tab2)
        // tab2 is active (appendTab sets activeTabId)
        #expect(store.activeTabId == tab2.id)
        store.flush()

        // Act — restore
        let persistor2 = WorkspacePersistor(workspacesDir: tempDir)
        let store2 = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: persistor2)
        store2.restore()

        // Assert — temporary tab pruned, activeTabId points to surviving tab
        #expect(store2.tabs.count == 1)
        #expect(store2.tabs[0].id == tab1.id)
        #expect(store2.activeTabId == tab1.id)
    }

    // MARK: - Orphaned Pane Pruning

    @Test

    func test_restore_prunesPanesWithMissingWorktree() {
        // Arrange — add a repo with a worktree, then create a worktree-bound pane
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/orphan-test-repo"))
        let wt = makeWorktree(name: "main", path: "/tmp/orphan-test-repo")
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [wt])

        let worktree = store.repos.first!.worktrees.first!
        let pane = store.createPane(
            launchDirectory: worktree.path,
            title: "Will become orphaned",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path),
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.flush()

        // Act — restore into a new store. The persisted repo has worktrees serialized,
        // but the pane's worktreeId won't match if worktrees were deleted.
        // Simulate by restoring, then creating a pane with a fabricated worktreeId
        // that doesn't exist in any repo.
        let orphanPane = store.createPane(
            launchDirectory: URL(fileURLWithPath: "/tmp/worktree"),
            title: "Orphaned",
            facets: PaneContextFacets(
                repoId: repo.id,
                worktreeId: UUID(),
                cwd: URL(fileURLWithPath: "/tmp/worktree")
            )
        )
        let orphanTab = Tab(paneId: orphanPane.id)
        store.appendTab(orphanTab)
        store.flush()

        let persistor2 = WorkspacePersistor(workspacesDir: tempDir)
        let store2 = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: persistor2)
        store2.restore()

        // Assert — the orphaned pane (with non-existent worktreeId) is pruned;
        // the valid pane (with existing worktreeId) survives
        #expect(store2.panes.count == 1, "Only the valid pane should survive")
        #expect((store2.pane(pane.id)) != nil)
        #expect(store2.tabs.count == 1, "Only the tab with valid pane should survive")
    }

    // MARK: - Dirty Flag

    @Test

    func test_isDirty_setOnMutation_clearedOnFlush() {
        // Arrange
        #expect(!(store.isDirty))

        // Act — mutation marks dirty
        _ = store.createPane()
        #expect(store.isDirty)

        // Act — flush clears dirty
        store.flush()
        #expect(!(store.isDirty))
    }

    @Test

    func test_isDirty_clearedAfterDebouncedSave() async throws {
        // Arrange — use zero debounce to avoid wall-clock waits in tests
        let fastPersistor = WorkspacePersistor(workspacesDir: tempDir)
        let fastStore = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: fastPersistor,
            persistDebounceDuration: .zero
        )
        fastStore.restore()
        _ = fastStore.createPane()
        #expect(fastStore.isDirty)

        // Act — allow scheduled debounce task to run
        for _ in 0..<80 where fastStore.isDirty {
            await Task.yield()
        }

        // Assert — debounced persistNow cleared the flag
        #expect(!(fastStore.isDirty))
    }

    @Test
    func debouncedAutosaveDampsIdenticalFailureReportsWithoutStoppingRetries() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.t8.damping.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.t8.damping.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let localRepositoryFactory = FailingThenSucceedingLocalRepositoryFactory(
            localQueue: localQueue,
            failuresBeforeSuccess: 3
        )
        let saveProbe = WorkspaceSQLiteSaveProbe()
        let sqliteDatastore = WorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            makeLocalRepository: { workspaceId in
                try localRepositoryFactory.makeLocalRepository(workspaceId: workspaceId)
            },
            probe: { event in
                await saveProbe.record(event)
            }
        )
        let clock = TestPushClock()
        var recoveryEvents: [PersistenceRecoveryEvent] = []
        let identityAtom = WorkspaceIdentityAtom()
        identityAtom.hydrate(
            workspaceId: workspaceId,
            workspaceName: "Autosave Damping",
            createdAt: Date(timeIntervalSince1970: 1_700_010_000)
        )
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            identityAtom: identityAtom,
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            ),
            sqliteDatastore: sqliteDatastore,
            persistDebounceDuration: .milliseconds(10),
            clock: clock,
            recoveryReporter: { event in recoveryEvents.append(event) }
        )

        func advanceNextDebouncedSave(after mutation: () -> Void) async {
            let nextSleepGeneration = clock.scheduledSleepGeneration
            mutation()
            await clock.waitForPendingSleepGeneration(nextSleepGeneration)
            clock.advance(by: .milliseconds(10))
        }

        func waitForSaveFailedRecoveryCount(_ expectedCount: Int) async {
            for _ in 0..<80
            where recoveryEvents.filter({ $0.recovery == .saveFailed }).count < expectedCount {
                await Task.yield()
            }
        }

        for attempt in 1...3 {
            await advanceNextDebouncedSave {
                store.setSidebarWidth(CGFloat(300 + attempt))
            }
            await saveProbe.waitForSaveCount(atLeast: attempt)
            await saveProbe.waitForFailedSaveCount(atLeast: attempt)
            await waitForSaveFailedRecoveryCount(attempt)
        }
        #expect(await saveProbe.saveCount == 3)
        #expect(await saveProbe.failedSaveCount == 3)
        #expect(localRepositoryFactory.openAttemptCount == 3)
        #expect(recoveryEvents.filter { $0.recovery == .saveFailed }.count == 3)
        #expect(store.isDirty)

        await advanceNextDebouncedSave {
            store.setSidebarWidth(304)
        }
        await saveProbe.waitForSaveCount(atLeast: 4)
        await saveProbe.waitForSucceededSaveCount(atLeast: 1)

        #expect(await saveProbe.saveCount == 4)
        #expect(await saveProbe.failedSaveCount == 3)
        #expect(await saveProbe.succeededSaveCount == 1)
        #expect(localRepositoryFactory.openAttemptCount == 4)
        #expect(recoveryEvents.filter { $0.recovery == .saveFailed }.count == 3)
        #expect(!store.isDirty)

        await advanceNextDebouncedSave {
            store.setSidebarWidth(305)
        }
        await saveProbe.waitForSaveCount(atLeast: 5)
        await saveProbe.waitForSucceededSaveCount(atLeast: 2)

        #expect(await saveProbe.saveCount == 5)
        #expect(await saveProbe.succeededSaveCount == 2)
        #expect(await saveProbe.failedSaveCount == 3)
        #expect(localRepositoryFactory.openAttemptCount == 4)
        #expect(recoveryEvents.filter { $0.recovery == .saveFailed }.count == 3)
        #expect(!store.isDirty)
    }

    @Test
    func test_isDirty_setOnDirectPaneAtomMutation() async {
        #expect(!(store.isDirty))

        _ = store.paneAtom.createPane()

        for _ in 0..<10 where !store.isDirty {
            await Task.yield()
        }

        #expect(store.isDirty)
    }

    @Test
    func test_repositoryTopologyStore_isDirty_setOnDirectTopologyAtomMutation() async {
        let topologyAtom = RepositoryTopologyAtom()
        let topologyStore = RepositoryTopologyStore(atom: topologyAtom)
        await topologyStore.restoreAsync(for: UUID())
        topologyStore.startObserving()
        #expect(!topologyStore.isDirty)

        _ = topologyAtom.addRepo(at: URL(fileURLWithPath: "/tmp/direct-topology"))

        for _ in 0..<10 where !topologyStore.isDirty {
            await Task.yield()
        }

        #expect(topologyStore.isDirty)
    }

    @Test
    func test_zoomPresentationChangeDoesNotDirtyWorkspacePersistence() async {
        let pane = store.paneAtom.createPane()
        let tab = Tab(paneId: pane.id)
        store.tabLayoutAtom.appendTab(tab)
        #expect(store.flush())
        #expect(!store.isDirty)

        store.tabLayoutAtom.toggleZoom(paneId: pane.id, inTab: tab.id)

        for _ in 0..<10 where store.isDirty {
            await Task.yield()
        }

        #expect(!store.isDirty)
    }

    @Test
    func test_isDirty_setOnDirectTabWriteOwnerMutation() async {
        let pane = store.paneAtom.createPane()
        let tab = Tab(paneId: pane.id)
        store.tabLayoutAtom.appendTab(tab)
        #expect(store.flush())
        #expect(!store.isDirty)

        store.tabGraphAtom.replaceStates([])

        for _ in 0..<10 where !store.isDirty {
            await Task.yield()
        }

        #expect(store.isDirty)
    }

    @Test
    func test_isDirty_setOnActiveTabCursorMutation() async {
        let firstPane = store.createPane()
        let firstTab = Tab(paneId: firstPane.id)
        store.appendTab(firstTab)
        let secondPane = store.createPane()
        let secondTab = Tab(paneId: secondPane.id)
        store.appendTab(secondTab)
        #expect(store.activeTabId == secondTab.id)
        #expect(store.flush())
        #expect(!store.isDirty)

        store.setActiveTab(firstTab.id)

        for _ in 0..<10 where !store.isDirty {
            await Task.yield()
        }

        #expect(store.isDirty)
    }

    @Test
    func test_isDirty_setOnActiveArrangementCursorMutation() async throws {
        let firstPane = store.createPane()
        let tab = Tab(paneId: firstPane.id)
        store.appendTab(tab)
        let secondPane = store.createPane()
        #expect(
            store.insertPane(
                secondPane.id,
                inTab: tab.id,
                at: firstPane.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            ))
        let customArrangementId = try #require(store.createArrangement(name: "Focus", inTab: tab.id))
        #expect(store.flush())
        #expect(!store.isDirty)

        store.switchArrangement(to: customArrangementId, inTab: tab.id)

        for _ in 0..<10 where !store.isDirty {
            await Task.yield()
        }

        #expect(store.isDirty)
    }

    @Test
    func test_isDirty_setOnActivePaneCursorMutation() async {
        let firstPane = store.createPane()
        let tab = Tab(paneId: firstPane.id)
        store.appendTab(tab)
        let secondPane = store.createPane()
        #expect(
            store.insertPane(
                secondPane.id,
                inTab: tab.id,
                at: firstPane.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            ))
        #expect(store.tab(tab.id)?.activePaneId == secondPane.id)
        #expect(store.flush())
        #expect(!store.isDirty)

        store.setActivePane(firstPane.id, inTab: tab.id)

        for _ in 0..<10 where !store.isDirty {
            await Task.yield()
        }

        #expect(store.isDirty)
    }

    @Test
    func test_isDirty_setOnActiveDrawerChildCursorMutation() async throws {
        let parentPane = store.createPane()
        let tab = Tab(paneId: parentPane.id)
        store.appendTab(tab)
        let firstDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let secondDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        #expect(store.drawerView(forParent: parentPane.id)?.activeChildId == secondDrawerPane.id)
        #expect(store.flush())
        #expect(!store.isDirty)

        store.setActiveDrawerPane(firstDrawerPane.id, in: parentPane.id)

        for _ in 0..<10 where !store.isDirty {
            await Task.yield()
        }

        #expect(store.isDirty)
    }

    @Test
    func test_repoEnrichmentDisplayChangeDoesNotDirtyWorkspacePersistence() async throws {
        let persistedDir = FileManager.default.temporaryDirectory
            .appending(path: "workspace-store-derived-display-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: persistedDir)
        let repoId = UUID()
        let worktreeId = UUID()
        let repoPath = URL(filePath: "/tmp/project-dev/agent-studio")
        let worktreePath = repoPath.appending(path: "sqlite")
        let pane = Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                launchDirectory: worktreePath,
                title: "Terminal",
                facets: PaneContextFacets(repoId: repoId, worktreeId: worktreeId, cwd: worktreePath)
            )
        )
        let tab = Tab(paneId: pane.id)
        #expect(persistor.ensureDirectory())
        try persistor.save(
            .init(
                repos: [CanonicalRepo(id: repoId, name: "agent-studio", repoPath: repoPath)],
                worktrees: [CanonicalWorktree(id: worktreeId, repoId: repoId, name: "sqlite", path: worktreePath)],
                panes: [pane],
                tabs: [tab],
                activeTabId: tab.id
            )
        )

        let atoms = AtomRegistry()
        let clock = TestPushClock()
        let scopedStore = WorkspaceStore(
            workspacePersistenceRevisionOwner: atoms.workspacePersistenceRevisionOwner,
            identityAtom: atoms.workspaceIdentity,
            windowMemoryAtom: atoms.workspaceWindowMemory,
            repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
            paneAtom: atoms.workspacePane,
            tabShellAtom: atoms.workspaceTabShell,
            tabArrangementAtom: atoms.workspaceTabArrangement,
            tabLayoutAtom: atoms.workspaceTabLayout,
            mutationCoordinator: atoms.workspaceMutationCoordinator,
            persistor: persistor,
            persistDebounceDuration: .seconds(1),
            clock: clock
        )
        scopedStore.restore()
        await Task.yield()
        #expect(!scopedStore.isDirty)
        #expect(clock.pendingSleepCount == 0)

        let restoredPane = try #require(scopedStore.pane(pane.id))
        #expect(restoredPane.repoId == repoId)
        #expect(restoredPane.worktreeId == worktreeId)
        #expect(restoredPane.metadata.cwd == worktreePath)
        #expect(scopedStore.activeTabId == tab.id)

        atoms.repoEnrichmentCache.setRepoEnrichment(
            .resolvedRemote(
                repoId: repoId,
                raw: RawRepoOrigin(origin: "origin-url", upstream: "upstream-url"),
                identity: RepoIdentity(
                    groupKey: "org",
                    remoteSlug: "org/agent-studio",
                    organizationName: "org",
                    displayName: "agent-studio"
                ),
                updatedAt: Date(timeIntervalSince1970: 1)
            )
        )
        await Task.yield()

        let derivedPane = try #require(scopedStore.pane(pane.id))
        #expect(derivedPane.metadata.facets.organizationName == "org")
        #expect(derivedPane.metadata.facets.origin == "origin-url")
        #expect(!scopedStore.isDirty)
        #expect(clock.pendingSleepCount == 0)
        #expect(scopedStore.flush())

        switch persistor.load() {
        case .loaded(let persistedState):
            let persistedPane = try #require(persistedState.panes.first)
            #expect(persistedPane.metadata.facets.organizationName == nil)
            #expect(persistedPane.metadata.facets.origin == nil)
            #expect(persistedPane.metadata.facets.upstream == nil)
        case .missing:
            Issue.record("Expected workspace state file after flush")
        case .corrupt(let error):
            Issue.record("Expected decodable workspace state, got \(error)")
        }
    }

    // MARK: - Undo

    @Test

    func test_snapshotForClose_capturesState() {
        // Arrange
        let pane = store.createPane()
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        // Act
        let snapshot = store.snapshotForClose(tabId: tab.id)

        // Assert
        #expect((snapshot) != nil)
        #expect(snapshot?.tab.id == tab.id)
        #expect(snapshot?.panes.count == 1)
        #expect(snapshot?.tabIndex == 0)
    }

    @Test

    func test_restoreFromSnapshot_reinsertTab() {
        // Arrange
        let pane = store.createPane()
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        let snapshot = store.snapshotForClose(tabId: tab.id)!

        // Act — remove tab and pane, then restore
        store.removeTab(tab.id)
        store.removePane(pane.id)
        #expect(store.tabs.isEmpty)
        #expect(store.panes.isEmpty)

        store.restoreFromSnapshot(snapshot)

        // Assert
        #expect(store.tabs.count == 1)
        #expect(store.tabs[0].id == tab.id)
        #expect(store.panes.count == 1)
        #expect(store.activeTabId == tab.id)
    }

    // MARK: - Worktree ID Stability

    @Test

    func test_updateRepoWorktrees_preservesExistingIds() {
        // Arrange — add repo then seed initial worktrees
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/wt-test-repo"))
        let wt1 = makeWorktree(repoId: repo.id, name: "main", path: "/tmp/wt-test-repo/main")
        let wt2 = makeWorktree(repoId: repo.id, name: "feat", path: "/tmp/wt-test-repo/feat")
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [wt1, wt2])

        let storedWt1Id = store.repos.first(where: { $0.id == repo.id })!.worktrees[0].id
        let storedWt2Id = store.repos.first(where: { $0.id == repo.id })!.worktrees[1].id

        // Create a pane referencing wt1's ID
        let pane = store.createPane(
            launchDirectory: store.repos.first!.worktrees.first!.path,
            facets: PaneContextFacets(
                repoId: repo.id, worktreeId: storedWt1Id, cwd: store.repos.first!.worktrees.first!.path)
        )

        // Act — simulate refresh with fresh Worktree instances (new UUIDs, same paths)
        let freshWt1 = makeWorktree(repoId: repo.id, name: "main-updated", path: "/tmp/wt-test-repo/main")
        let freshWt2 = makeWorktree(repoId: repo.id, name: "feat-updated", path: "/tmp/wt-test-repo/feat")
        #expect(freshWt1.id != storedWt1Id, "precondition: fresh worktree has different UUID")

        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [freshWt1, freshWt2])

        // Assert — IDs preserved, names updated
        let updated = store.repos.first(where: { $0.id == repo.id })!
        #expect(updated.worktrees.count == 2)
        #expect(updated.worktrees[0].id == storedWt1Id, "existing worktree ID preserved")
        #expect(updated.worktrees[1].id == storedWt2Id, "existing worktree ID preserved")
        #expect(updated.worktrees[0].name == "main-updated", "name updated from discovery")
        #expect(updated.worktrees[1].name == "feat-updated", "name updated from discovery")

        // Pane still resolves
        #expect(pane.worktreeId == storedWt1Id)
        #expect((store.worktree(storedWt1Id)) != nil)
    }

    @Test

    func test_updateRepoWorktrees_addsNewWorktrees() {
        // Arrange
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/wt-test-repo2"))
        let wt1 = makeWorktree(repoId: repo.id, name: "main", path: "/tmp/wt-test-repo2/main")
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [wt1])
        let storedWt1Id = store.repos.first(where: { $0.id == repo.id })!.worktrees[0].id

        // Act — refresh adds a new worktree
        let freshWt1 = makeWorktree(repoId: repo.id, name: "main", path: "/tmp/wt-test-repo2/main")
        let newWt = makeWorktree(repoId: repo.id, name: "hotfix", path: "/tmp/wt-test-repo2/hotfix")
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [freshWt1, newWt])

        // Assert
        let updated = store.repos.first(where: { $0.id == repo.id })!
        #expect(updated.worktrees.count == 2)
        #expect(updated.worktrees[0].id == storedWt1Id, "existing ID preserved")
        #expect(updated.worktrees[1].id == newWt.id, "new worktree gets its own ID")
    }

    @Test

    func test_updateRepoWorktrees_removesDeletedWorktrees() {
        // Arrange
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/wt-test-repo3"))
        let wt1 = makeWorktree(repoId: repo.id, name: "main", path: "/tmp/wt-test-repo3/main")
        let wt2 = makeWorktree(repoId: repo.id, name: "feat", path: "/tmp/wt-test-repo3/feat")
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [wt1, wt2])
        let storedWt1Id = store.repos.first(where: { $0.id == repo.id })!.worktrees[0].id

        // Act — refresh returns only wt1 (wt2 was deleted)
        let freshWt1 = makeWorktree(repoId: repo.id, name: "main", path: "/tmp/wt-test-repo3/main")
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [freshWt1])

        // Assert — only wt1 remains
        let updated = store.repos.first(where: { $0.id == repo.id })!
        #expect(updated.worktrees.count == 1)
        #expect(updated.worktrees[0].id == storedWt1Id)
    }

    @Test

    func test_updateRepoWorktrees_noopWhenMergedResultUnchanged() {
        // Arrange
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/wt-test-repo4"))
        let wt1 = makeWorktree(repoId: repo.id, name: "main", path: "/tmp/wt-test-repo4/main")
        let wt2 = makeWorktree(repoId: repo.id, name: "feat", path: "/tmp/wt-test-repo4/feat")
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [wt1, wt2])
        let before = store.repos.first(where: { $0.id == repo.id })!

        // Act — same effective data, but fresh worktree instances
        let sameWt1 = makeWorktree(repoId: repo.id, name: "main", path: "/tmp/wt-test-repo4/main")
        let sameWt2 = makeWorktree(repoId: repo.id, name: "feat", path: "/tmp/wt-test-repo4/feat")
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [sameWt1, sameWt2])
        let after = store.repos.first(where: { $0.id == repo.id })!

        // Assert — IDs/worktrees unchanged
        #expect(after.worktrees == before.worktrees)
    }

    // MARK: - Restore Validation

    @Test

    func test_restore_repairsStaleActiveArrangementId() throws {
        // Arrange — persist a tab with an activeArrangementId that doesn't match any arrangement
        let pane = makePane()
        let layout = Layout(paneId: pane.id)
        let arrangement = PaneArrangement(name: "Default", isDefault: true, layout: layout)
        let tab = Tab(
            panes: [pane.id],
            arrangements: [arrangement],
            activeArrangementId: UUID(),  // stale — doesn't match `arrangement.id`
            activePaneId: pane.id
        )
        var state = WorkspacePersistor.PersistableState()
        state.panes = [pane]
        state.tabs = [tab]
        state.activeTabId = tab.id
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        try persistor.save(state)

        // Act
        let store2 = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: persistor)
        store2.restore()

        // Assert — activeArrangementId repaired to the default arrangement
        #expect(store2.tabs.count == 1)
        #expect(store2.tabs[0].activeArrangementId == arrangement.id)
    }

    @Test

    func test_restore_repairsStaleActivePaneId() throws {
        // Arrange — persist a tab whose activePaneId doesn't exist in the layout
        let pane = makePane()
        let layout = Layout(paneId: pane.id)
        let arrangement = PaneArrangement(name: "Default", isDefault: true, layout: layout)
        let tab = Tab(
            panes: [pane.id],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: UUID()  // stale — not in layout
        )
        var state = WorkspacePersistor.PersistableState()
        state.panes = [pane]
        state.tabs = [tab]
        state.activeTabId = tab.id
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        try persistor.save(state)

        // Act
        let store2 = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: persistor)
        store2.restore()

        // Assert — activePaneId repaired to the first pane in layout
        #expect(store2.tabs[0].activePaneId == pane.id)
    }

    @Test

    func test_restore_repairsMissingDefaultArrangement() throws {
        // Arrange — construct a valid tab, then corrupt it before persisting
        let pane = makePane()
        var tab = Tab(paneId: pane.id)
        // Corrupt: clear the isDefault flag
        tab.arrangements[0].isDefault = false
        var state = WorkspacePersistor.PersistableState()
        state.panes = [pane]
        state.tabs = [tab]
        state.activeTabId = tab.id
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        try persistor.save(state)

        // Act
        let store2 = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: persistor)
        store2.restore()

        // Assert — first arrangement promoted to default
        #expect(store2.tabs.count == 1)
        #expect(store2.tabs[0].arrangements[0].isDefault)
    }

    @Test

    func test_restore_syncsPanesListWithLayoutPaneIds() throws {
        // Arrange — persist a tab whose panes list drifted from layout
        let p1 = makePane()
        let p2 = makePane()
        let layout = Layout(paneId: p1.id)
            .inserting(paneId: p2.id, at: p1.id, direction: .horizontal, position: .after, sizingMode: .halveTarget)!
        let arrangement = PaneArrangement(name: "Default", isDefault: true, layout: layout)
        let tab = Tab(
            panes: [p1.id],  // missing p2 — drifted
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: p1.id
        )
        var state = WorkspacePersistor.PersistableState()
        state.panes = [p1, p2]
        state.tabs = [tab]
        state.activeTabId = tab.id
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        try persistor.save(state)

        // Act
        let store2 = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: persistor)
        store2.restore()

        // Assert — panes list synced with layout
        #expect(Set(store2.tabs[0].panes) == Set([p1.id, p2.id]))
    }

    @Test

    func test_restore_repairsCrossTabDuplicatePanes() throws {
        // Arrange — persist two tabs sharing the same pane (corruption)
        let p1 = makePane()
        let p2 = makePane()
        let layout1 = Layout(paneId: p1.id)
            .inserting(paneId: p2.id, at: p1.id, direction: .horizontal, position: .after, sizingMode: .halveTarget)!
        let layout2 = Layout(paneId: p2.id)  // p2 duplicated across tabs
        let arr1 = PaneArrangement(name: "Default", isDefault: true, layout: layout1)
        let arr2 = PaneArrangement(name: "Default", isDefault: true, layout: layout2)
        let tab1 = Tab(
            panes: [p1.id, p2.id], arrangements: [arr1],
            activeArrangementId: arr1.id, activePaneId: p1.id)
        let tab2 = Tab(
            panes: [p2.id], arrangements: [arr2],
            activeArrangementId: arr2.id, activePaneId: p2.id)
        var state = WorkspacePersistor.PersistableState()
        state.panes = [p1, p2]
        state.tabs = [tab1, tab2]
        state.activeTabId = tab1.id
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        try persistor.save(state)

        // Act
        let store2 = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: persistor)
        store2.restore()

        // Assert — p2 should only appear in ONE tab (first wins)
        let allPanes = store2.tabs.flatMap(\.panes)
        let p2Count = allPanes.filter { $0 == p2.id }.count
        #expect(p2Count == 1, "Duplicate pane should be repaired to appear in only one tab")
    }

    @Test

    func test_restore_repairsActivePaneIdAfterDuplicateRemoval() throws {
        // Arrange — tab2's active pane is a duplicate that will be removed
        let p1 = makePane()
        let p2 = makePane()
        let layout1 = Layout(paneId: p1.id)
            .inserting(paneId: p2.id, at: p1.id, direction: .horizontal, position: .after, sizingMode: .halveTarget)!
        let layout2 = Layout(paneId: p2.id)
        let arr1 = PaneArrangement(name: "Default", isDefault: true, layout: layout1)
        let arr2 = PaneArrangement(name: "Default", isDefault: true, layout: layout2)
        let tab1 = Tab(
            panes: [p1.id, p2.id], arrangements: [arr1],
            activeArrangementId: arr1.id, activePaneId: p1.id)
        let tab2 = Tab(
            panes: [p2.id], arrangements: [arr2],
            activeArrangementId: arr2.id, activePaneId: p2.id)  // active is the duplicate
        var state = WorkspacePersistor.PersistableState()
        state.panes = [p1, p2]
        state.tabs = [tab1, tab2]
        state.activeTabId = tab1.id
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        try persistor.save(state)

        // Act
        let store2 = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: persistor)
        store2.restore()

        // Assert — if tab2 survives, its activePaneId should not be p2 (was removed)
        // Tab2 may be empty and removed, which is also a valid repair outcome
        for tab in store2.tabs {
            if let apId = tab.activePaneId {
                #expect(tab.activeArrangement.layout.paneIds.contains(apId))
            }
        }
    }

    @Test

    func test_persistence_activeTabIdNotMutatedDuringSave() {
        // Arrange — create tabs: tab1 has temporary pane (pruned on save), tab2 is persistent
        let p1 = store.createPane(
            lifetime: .temporary)
        let tab1 = Tab(paneId: p1.id)
        store.appendTab(tab1)
        let p2 = store.createPane()
        let tab2 = Tab(paneId: p2.id)
        store.appendTab(tab2)
        store.setActiveTab(tab1.id)  // select the temporary tab

        // Act — flush() calls persistNow() which prunes tab1 (all-temporary)
        // from the persisted copy. This should NOT change live activeTabId.
        _ = store.flush()

        // Assert — live activeTabId still points to tab1
        #expect(store.activeTabId == tab1.id, "flush/persistNow should not mutate live activeTabId")
    }

    // MARK: - moveTabByDelta

    @Test

    func test_moveTabByDelta_movesForward() {
        // Arrange
        let p1 = store.createPane()
        let p2 = store.createPane()
        let p3 = store.createPane()
        let tab1 = Tab(paneId: p1.id)
        let tab2 = Tab(paneId: p2.id)
        let tab3 = Tab(paneId: p3.id)
        store.appendTab(tab1)
        store.appendTab(tab2)
        store.appendTab(tab3)

        // Act — move tab1 forward by 2
        store.moveTabByDelta(tabId: tab1.id, delta: 2)

        // Assert — tab1 is now at index 2
        #expect(store.tabs[0].id == tab2.id)
        #expect(store.tabs[1].id == tab3.id)
        #expect(store.tabs[2].id == tab1.id)
    }

    @Test

    func test_moveTabByDelta_movesBackward() {
        // Arrange
        let p1 = store.createPane()
        let p2 = store.createPane()
        let p3 = store.createPane()
        let tab1 = Tab(paneId: p1.id)
        let tab2 = Tab(paneId: p2.id)
        let tab3 = Tab(paneId: p3.id)
        store.appendTab(tab1)
        store.appendTab(tab2)
        store.appendTab(tab3)

        // Act — move tab3 backward by 1
        store.moveTabByDelta(tabId: tab3.id, delta: -1)

        // Assert — tab3 is now at index 1
        #expect(store.tabs[0].id == tab1.id)
        #expect(store.tabs[1].id == tab3.id)
        #expect(store.tabs[2].id == tab2.id)
    }

    @Test

    func test_moveTabByDelta_clampsAtEnd() {
        // Arrange
        let p1 = store.createPane()
        let p2 = store.createPane()
        let tab1 = Tab(paneId: p1.id)
        let tab2 = Tab(paneId: p2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Act — move tab1 forward by 100 (should clamp)
        store.moveTabByDelta(tabId: tab1.id, delta: 100)

        // Assert — tab1 clamped to last position
        #expect(store.tabs[0].id == tab2.id)
        #expect(store.tabs[1].id == tab1.id)
    }

    @Test

    func test_moveTabByDelta_clampsAtStart() {
        // Arrange
        let p1 = store.createPane()
        let p2 = store.createPane()
        let tab1 = Tab(paneId: p1.id)
        let tab2 = Tab(paneId: p2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Act — move tab2 backward by 100 (should clamp to 0)
        store.moveTabByDelta(tabId: tab2.id, delta: -100)

        // Assert — tab2 clamped to first position
        #expect(store.tabs[0].id == tab2.id)
        #expect(store.tabs[1].id == tab1.id)
    }

    @Test

    func test_moveTabByDelta_singleTab_noOp() {
        // Arrange
        let p1 = store.createPane()
        let tab1 = Tab(paneId: p1.id)
        store.appendTab(tab1)

        // Act — single tab, delta should be ignored
        store.moveTabByDelta(tabId: tab1.id, delta: 1)

        // Assert — unchanged
        #expect(store.tabs.count == 1)
        #expect(store.tabs[0].id == tab1.id)
    }

    // MARK: - setActiveTab

    @Test

    func test_setActiveTab_setsTabId() {
        // Arrange
        let p1 = store.createPane()
        let p2 = store.createPane()
        let tab1 = Tab(paneId: p1.id)
        let tab2 = Tab(paneId: p2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Act
        store.setActiveTab(tab2.id)

        // Assert
        #expect(store.activeTabId == tab2.id)
    }

    @Test

    func test_setActiveTab_nil_clearsActiveTab() {
        // Arrange
        let p1 = store.createPane()
        let tab1 = Tab(paneId: p1.id)
        store.appendTab(tab1)
        store.setActiveTab(tab1.id)

        // Act
        store.setActiveTab(nil)

        // Assert
        #expect((store.activeTabId) == nil)
    }

    // MARK: - setActivePane

    @Test

    func test_setActivePane_validPane() {
        // Arrange
        let p1 = store.createPane()
        let p2 = store.createPane()
        let tab = makeTab(paneIds: [p1.id, p2.id], activePaneId: p1.id)
        store.appendTab(tab)

        // Act
        store.setActivePane(p2.id, inTab: tab.id)

        // Assert
        #expect(store.tabs[0].activePaneId == p2.id)
    }

    @Test

    func test_setActivePane_invalidPane_rejected() {
        // Arrange
        let p1 = store.createPane()
        let tab = Tab(paneId: p1.id)
        store.appendTab(tab)

        // Act — set to a pane ID that doesn't exist in the tab
        let bogus = UUID()
        store.setActivePane(bogus, inTab: tab.id)

        // Assert — unchanged
        #expect(store.tabs[0].activePaneId == p1.id)
    }

    @Test

    func test_setActivePane_nil_clearsActivePane() {
        // Arrange
        let p1 = store.createPane()
        let tab = Tab(paneId: p1.id)
        store.appendTab(tab)

        // Act
        store.setActivePane(nil, inTab: tab.id)

        // Assert
        #expect((store.tabs[0].activePaneId) == nil)
    }

    // MARK: - toggleZoom

    @Test

    func test_toggleZoom_setsZoomedPaneId() {
        // Arrange
        let p1 = store.createPane()
        let p2 = store.createPane()
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)

        // Act — zoom in
        store.toggleZoom(paneId: p1.id, inTab: tab.id)

        // Assert
        #expect(store.tabs[0].zoomedPaneId == p1.id)
    }

    @Test

    func test_toggleZoom_togglesOff() {
        // Arrange
        let p1 = store.createPane()
        let p2 = store.createPane()
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)
        store.toggleZoom(paneId: p1.id, inTab: tab.id)

        // Act — toggle off
        store.toggleZoom(paneId: p1.id, inTab: tab.id)

        // Assert
        #expect((store.tabs[0].zoomedPaneId) == nil)
    }

    @Test

    func test_toggleZoom_invalidPane_noOp() {
        // Arrange
        let p1 = store.createPane()
        let tab = Tab(paneId: p1.id)
        store.appendTab(tab)

        // Act — zoom on a pane that isn't in the layout
        let bogus = UUID()
        store.toggleZoom(paneId: bogus, inTab: tab.id)

        // Assert — no zoom set
        #expect((store.tabs[0].zoomedPaneId) == nil)
    }

    // MARK: - insertPane clears zoom

    @Test

    func test_insertPane_clearsZoom() {
        // Arrange
        let p1 = store.createPane()
        let p2 = store.createPane()
        let tab = Tab(paneId: p1.id)
        store.appendTab(tab)
        store.toggleZoom(paneId: p1.id, inTab: tab.id)
        #expect((store.tabs[0].zoomedPaneId) != nil)

        // Act — insert a new pane
        store.insertPane(
            p2.id, inTab: tab.id, at: p1.id, direction: .horizontal, position: .after, sizingMode: .halveTarget)

        // Assert — zoom cleared
        #expect((store.tabs[0].zoomedPaneId) == nil)
    }

    // MARK: - removePaneFromLayout clears zoom

    @Test

    func test_removePaneFromLayout_clearsZoomOnRemovedPane() {
        // Arrange
        let p1 = store.createPane()
        let p2 = store.createPane()
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)
        store.toggleZoom(paneId: p1.id, inTab: tab.id)
        #expect(store.tabs[0].zoomedPaneId == p1.id)

        // Act — remove the zoomed pane
        store.removePaneFromLayout(p1.id, inTab: tab.id)

        // Assert — zoom cleared
        #expect((store.tabs[0].zoomedPaneId) == nil)
    }

    // MARK: - resizePane

    @Test

    func test_resizePane_changesRatio() {
        // Arrange
        let p1 = store.createPane()
        let p2 = store.createPane()
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)
        guard let dividerId = store.tabs[0].layout.dividerIds.first else {
            Issue.record("Expected divider")
            return
        }

        // Act
        store.resizePane(tabId: tab.id, splitId: dividerId, ratio: 0.7)

        // Assert
        #expect(abs((store.tabs[0].layout.ratioForSplit(dividerId) ?? 0.0) - (0.7)) <= 0.001)
    }

    @Test
    func test_resizeVisiblePanePair_preservesMinimizedRatioAndUnrelatedPane() {
        let p1 = store.createPane()
        let p2 = store.createPane()
        let p3 = store.createPane()
        let p4 = store.createPane()
        let tab = makeTab(paneIds: [p1.id, p2.id, p3.id, p4.id], activePaneId: p1.id)
        store.appendTab(tab)
        store.minimizePane(p2.id, inTab: tab.id)
        let before = store.tabs[0].layout

        store.resizeVisiblePanePair(tabId: tab.id, leftPaneId: p1.id, rightPaneId: p3.id, ratio: 0.7)

        let after = store.tabs[0].layout
        #expect(abs((after.ratioForPanePair(leftPaneId: p1.id, rightPaneId: p3.id) ?? 0) - 0.7) <= 0.001)
        #expect(abs((after.paneRatio(p2.id) ?? 0) - (before.paneRatio(p2.id) ?? 0)) <= 1e-9)
        #expect(abs((after.paneRatio(p4.id) ?? 0) - (before.paneRatio(p4.id) ?? 0)) <= 1e-9)
    }

    // MARK: - resizePaneByDelta

    @Test

    func test_resizePaneByDelta_adjustsRatio() {
        // Arrange
        let p1 = store.createPane()
        let p2 = store.createPane()
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)
        guard let dividerId = store.tabs[0].layout.dividerIds.first else {
            Issue.record("Expected divider")
            return
        }
        let ratioBefore = store.tabs[0].layout.ratioForSplit(dividerId)

        // Act — resize p1 to the right (increase left pane)
        store.resizePaneByDelta(tabId: tab.id, paneId: p1.id, direction: .right, amount: 10)

        // Assert — ratio changed
        #expect(store.tabs[0].layout.ratioForSplit(dividerId) != ratioBefore)
    }

    @Test
    func test_resizePaneByDelta_skipsMinimizedNeighbor() {
        let p1 = store.createPane()
        let p2 = store.createPane()
        let p3 = store.createPane()
        let tab = makeTab(paneIds: [p1.id, p2.id, p3.id], activePaneId: p1.id)
        store.appendTab(tab)
        store.minimizePane(p2.id, inTab: tab.id)
        let before = store.tabs[0].layout

        store.resizePaneByDelta(tabId: tab.id, paneId: p1.id, direction: .right, amount: 10)

        let after = store.tabs[0].layout
        #expect(abs((after.paneRatio(p2.id) ?? 0) - (before.paneRatio(p2.id) ?? 0)) <= 1e-9)
        #expect((after.ratioForPanePair(leftPaneId: p1.id, rightPaneId: p3.id) ?? 0) > 0.5)
    }

    @Test
    func test_resizePaneByDelta_noOpsWhenMinimizedNeighborHasNoVisiblePartner() {
        let p1 = store.createPane()
        let p2 = store.createPane()
        let p3 = store.createPane()
        let tab = makeTab(paneIds: [p1.id, p2.id, p3.id], activePaneId: p2.id)
        store.appendTab(tab)
        store.minimizePane(p3.id, inTab: tab.id)
        let before = store.tabs[0].layout

        store.resizePaneByDelta(tabId: tab.id, paneId: p2.id, direction: .right, amount: 10)

        #expect(store.tabs[0].layout == before)
    }

    @Test

    func test_resizePaneByDelta_whileZoomed_noOp() {
        // Arrange
        let p1 = store.createPane()
        let p2 = store.createPane()
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)
        store.toggleZoom(paneId: p1.id, inTab: tab.id)
        guard let dividerId = store.tabs[0].layout.dividerIds.first else {
            Issue.record("Expected divider")
            return
        }
        let ratioBefore = store.tabs[0].layout.ratioForSplit(dividerId)

        // Act — try to resize while zoomed
        store.resizePaneByDelta(tabId: tab.id, paneId: p1.id, direction: .right, amount: 10)

        // Assert — ratio unchanged
        #expect(store.tabs[0].layout.ratioForSplit(dividerId) == ratioBefore)
    }

    // MARK: - addRepo / removeRepo

    @Test

    func test_addRepo_addsToRepos() {
        // Act
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/new-repo"))

        // Assert
        #expect(store.repos.count == 1)
        #expect(store.repos[0].id == repo.id)
        #expect(store.repos[0].name == "new-repo")
        #expect(store.repos[0].worktrees.count == 1)
        #expect(store.repos[0].worktrees[0].isMainWorktree)
        #expect(store.repos[0].worktrees[0].path == URL(fileURLWithPath: "/tmp/new-repo"))
    }

    @Test

    func test_addRepo_duplicate_returnsExisting() {
        // Arrange
        let path = URL(fileURLWithPath: "/tmp/dup-repo")
        let first = store.addRepo(at: path)

        // Act
        let second = store.addRepo(at: path)

        // Assert — same repo returned, not duplicated
        #expect(store.repos.count == 1)
        #expect(first.id == second.id)
        #expect(store.repos[0].worktrees.count == 1)
    }

    @Test

    func test_removeRepo_removesFromRepos() {
        // Arrange
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/del-repo"))
        #expect(store.repos.count == 1)

        // Act
        store.removeRepo(repo.id)

        // Assert
        #expect(store.repos.isEmpty)
    }

    // MARK: - setSidebarWidth / setWindowFrame

    @Test

    func test_setSidebarWidth_updatesValue() {
        // Act
        store.setSidebarWidth(300)

        // Assert
        #expect(store.sidebarWidth == 300)
    }

    @Test

    func test_setWindowFrame_updatesValue() {
        // Arrange
        let frame = CGRect(x: 100, y: 200, width: 800, height: 600)

        // Act
        store.setWindowFrame(frame)

        // Assert
        #expect(store.windowFrame == frame)
    }

    @Test

    func test_setWindowFrame_nil_clearsValue() {
        // Arrange
        store.setWindowFrame(CGRect(x: 0, y: 0, width: 100, height: 100))

        // Act
        store.setWindowFrame(nil)

        // Assert
        #expect((store.windowFrame) == nil)
    }

    // MARK: - extractPane clears zoom

    @Test

    func test_extractPane_clearsZoomOnExtractedPane() {
        // Arrange
        let p1 = store.createPane()
        let p2 = store.createPane()
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)
        store.toggleZoom(paneId: p1.id, inTab: tab.id)
        #expect(store.tabs[0].zoomedPaneId == p1.id)

        // Act — extract the zoomed pane
        let newTab = store.extractPane(p1.id, fromTab: tab.id)

        // Assert — old tab's zoom cleared
        #expect((newTab) != nil)
        #expect((store.tabs[0].zoomedPaneId) == nil)
    }

    // MARK: - removePaneFromLayout updates activePaneId

    @Test

    func test_removePaneFromLayout_updatesActivePaneIdWhenActiveRemoved() {
        // Arrange
        let p1 = store.createPane()
        let p2 = store.createPane()
        let tab = makeTab(paneIds: [p1.id, p2.id], activePaneId: p1.id)
        store.appendTab(tab)
        #expect(store.tabs[0].activePaneId == p1.id)

        // Act — remove the active pane
        store.removePaneFromLayout(p1.id, inTab: tab.id)

        // Assert — activePaneId updated to remaining pane
        #expect(store.tabs[0].activePaneId == p2.id)
    }

    // MARK: - WatchedPath

    @Test func addWatchedPath_addsAndMarksDirty() {
        // Arrange & Act
        let result = store.addWatchedPath(URL(fileURLWithPath: "/projects"))

        // Assert
        #expect(result != nil)
        #expect(store.watchedPaths.count == 1)
        #expect(store.watchedPaths[0].path.path == "/projects")
    }

    @Test func addWatchedPath_deduplicatesByStableKey() {
        // Arrange & Act
        store.addWatchedPath(URL(fileURLWithPath: "/projects"))
        store.addWatchedPath(URL(fileURLWithPath: "/projects"))

        // Assert
        #expect(store.watchedPaths.count == 1)
    }

    @Test func removeWatchedPath_removesById() {
        // Arrange
        let watchedPath = store.addWatchedPath(URL(fileURLWithPath: "/projects"))!

        // Act
        store.removeWatchedPath(watchedPath.id)

        // Assert
        #expect(store.watchedPaths.isEmpty)
    }
}

private actor WorkspaceSQLiteSaveProbe {
    private var saveEvents: Int = 0
    private var succeededSaveEvents: Int = 0
    private var failedSaveEvents: Int = 0
    private var waiters: [(minimum: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var succeededWaiters: [(minimum: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var failedWaiters: [(minimum: Int, continuation: CheckedContinuation<Void, Never>)] = []

    var saveCount: Int {
        saveEvents
    }

    var succeededSaveCount: Int {
        succeededSaveEvents
    }

    var failedSaveCount: Int {
        failedSaveEvents
    }

    func record(_ event: WorkspaceSQLiteDatastore.ProbeEvent) {
        switch event {
        case .saveWorkspaceSnapshot:
            saveEvents += 1
            resumeSatisfiedWaiters()
        case .saveWorkspaceSnapshotSucceeded:
            succeededSaveEvents += 1
            resumeSatisfiedSucceededWaiters()
        case .saveWorkspaceSnapshotFailed:
            failedSaveEvents += 1
            resumeSatisfiedFailedWaiters()
        case .loadWorkspaceSnapshot, .localRepositoryOpened:
            break
        }
    }

    func waitForSaveCount(atLeast minimum: Int) async {
        if saveEvents >= minimum {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append((minimum: minimum, continuation: continuation))
        }
    }

    func waitForSucceededSaveCount(atLeast minimum: Int) async {
        if succeededSaveEvents >= minimum {
            return
        }
        await withCheckedContinuation { continuation in
            succeededWaiters.append((minimum: minimum, continuation: continuation))
        }
    }

    func waitForFailedSaveCount(atLeast minimum: Int) async {
        if failedSaveEvents >= minimum {
            return
        }
        await withCheckedContinuation { continuation in
            failedWaiters.append((minimum: minimum, continuation: continuation))
        }
    }

    private func resumeSatisfiedWaiters() {
        var remaining: [(minimum: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in waiters {
            if saveEvents >= waiter.minimum {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        waiters = remaining
    }

    private func resumeSatisfiedSucceededWaiters() {
        var remaining: [(minimum: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in succeededWaiters {
            if succeededSaveEvents >= waiter.minimum {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        succeededWaiters = remaining
    }

    private func resumeSatisfiedFailedWaiters() {
        var remaining: [(minimum: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in failedWaiters {
            if failedSaveEvents >= waiter.minimum {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        failedWaiters = remaining
    }
}

private final class FailingThenSucceedingLocalRepositoryFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let localQueue: DatabaseQueue
    private let failuresBeforeSuccess: Int
    private var attempts: Int = 0

    init(localQueue: DatabaseQueue, failuresBeforeSuccess: Int) {
        self.localQueue = localQueue
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    var openAttemptCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return attempts
    }

    func makeLocalRepository(workspaceId requestedWorkspaceId: UUID) throws -> WorkspaceLocalRepository {
        lock.lock()
        attempts += 1
        let shouldFail = attempts <= failuresBeforeSuccess
        lock.unlock()

        if shouldFail {
            throw CocoaError(.fileNoSuchFile)
        }
        return WorkspaceLocalRepository(workspaceId: requestedWorkspaceId, databaseWriter: localQueue)
    }
}

@MainActor
private func yieldMainActor(times count: Int) async {
    for _ in 0..<count {
        await Task.yield()
    }
}
