import AgentStudioInfrastructure
import AppKit
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct WorkspaceSurfaceCoordinatorUndoRestoreTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    private let trustedBounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    private struct Harness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let runtime: SessionRuntime
        let coordinator: WorkspaceSurfaceCoordinator
        let tempDir: URL
        let surfaceManager: UndoRestoreSurfaceManager
    }

    private func makeHarness(
        createSurfaceResult: Result<ManagedSurface, SurfaceError> = .failure(.ghosttyNotInitialized),
        undoCloseResults: [ManagedSurface] = []
    ) -> Harness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-undo-restore-\(UUID().uuidString)")
        let store = WorkspaceStore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let surfaceManager = UndoRestoreSurfaceManager(
            createSurfaceResult: createSurfaceResult,
            undoCloseResults: undoCloseResults
        )
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: surfaceManager,
            runtimeRegistry: RuntimeRegistry(),
            windowLifecycleStore: WindowLifecycleAtom(),
            bridgePaneAttendance: BridgePaneAttendanceAtom()
        )
        return Harness(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            coordinator: coordinator,
            tempDir: tempDir,
            surfaceManager: surfaceManager
        )
    }

    private func makeRepoAndWorktree(_ store: WorkspaceStore, root: URL) -> (Repo, Worktree) {
        let repoPath = root.appending(path: "repo-\(UUID().uuidString)")
        let worktreePath = repoPath.appending(path: "wt-main")
        try? FileManager.default.createDirectory(at: repoPath, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: worktreePath, withIntermediateDirectories: true)

        let repo = store.addRepo(at: repoPath)
        let worktree = Worktree(repoId: repo.id, name: "wt-main", path: worktreePath)
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        return store.repositoryTopologyAtom.repoAndWorktree(containing: worktreePath) ?? (repo, worktree)
    }

    /// Returns a repo/worktree pair whose worktree is admitted into the topology atom, unlike
    /// `makeRepoAndWorktree`'s nested "wt-main" candidate: reconciling that nested candidate alone
    /// (without also carrying forward the auto-created root worktree) leaves the repo without a
    /// worktree at its root path, so `reconcileWorktrees` marks the repo unavailable and pane
    /// creation never stamps `worktreeId`/`repoId` onto the resulting pane. Callers that need a
    /// pane whose `worktreeId`/`repoId` actually resolve through `RepositoryTopologyAtom` (e.g.
    /// undo paths that look up `pane.worktreeId`) should use this helper instead.
    private func makeAdmittedRepoAndWorktree(_ store: WorkspaceStore, root: URL) -> (Repo, Worktree) {
        let repoPath = root.appending(path: "repo-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: repoPath, withIntermediateDirectories: true)
        let repo = store.addRepo(at: repoPath)
        return (repo, repo.worktrees[0])
    }

    private func makeWebviewPane(_ store: WorkspaceStore, title: String) -> Pane {
        let url = URL(string: "https://example.com/\(UUID().uuidString)")!
        return store.createPane(
            content: .webview(WebviewState(url: url, showNavigation: true)),
            metadata: PaneMetadata(title: title)
        )
    }

    private func makeWorktreePane(
        _ store: WorkspaceStore,
        repo: Repo,
        worktree: Worktree,
        title: String
    ) -> Pane {
        store.createPane(
            launchDirectory: worktree.path,
            title: title,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
    }

    @Test("close tab marks snapshot panes pending undo and undo restores active ownership")
    func closeTab_marksSnapshotPanesPendingUndo_andUndoRestoresActiveOwnership() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let firstPane = makeWebviewPane(harness.store, title: "First")
        let secondPane = makeWebviewPane(harness.store, title: "Second")
        let tab = Tab(paneId: firstPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.insertPane(
            secondPane.id,
            inTab: tab.id,
            at: firstPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )

        harness.coordinator.execute(.closeTab(tabId: tab.id))

        #expect(harness.store.tab(tab.id) == nil)
        for paneId in [firstPane.id, secondPane.id] {
            let closedPane = try #require(harness.store.pane(paneId))
            #expect(closedPane.residency.isPendingUndo)
            #expect(!closedPane.residency.isActive)
        }

        harness.coordinator.undoCloseTab()

        let restoredTab = try #require(harness.store.tab(tab.id))
        #expect(Set(restoredTab.allPaneIds) == Set([firstPane.id, secondPane.id]))
        for paneId in [firstPane.id, secondPane.id] {
            #expect(harness.store.pane(paneId)?.residency == .active)
        }
    }

    @Test("undoTabClose keeps tab only with successfully restored panes")
    func undoTabClose_partialRestore_removesFailedPanes() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let terminalPane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Terminal")
        let webviewPane = makeWebviewPane(harness.store, title: "Web")
        let tab = Tab(paneId: terminalPane.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            webviewPane.id,
            inTab: tab.id,
            at: terminalPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        harness.coordinator.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)

        harness.coordinator.execute(.closeTab(tabId: tab.id))
        harness.coordinator.undoCloseTab()

        guard let restoredTab = harness.store.tab(tab.id) else {
            Issue.record("Expected tab to remain after partial restore")
            return
        }
        #expect(restoredTab.paneIds == [webviewPane.id])
        #expect(harness.store.pane(terminalPane.id) == nil)
        #expect(harness.viewRegistry.view(for: webviewPane.id) != nil)
    }

    @Test("undoTabClose preserves drawer state when terminal restore is deferred by missing geometry")
    func undoTabClose_deferredTerminalRestore_preservesDrawerState() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let parentPane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Parent")
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let firstDrawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        let secondDrawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        let drawerId = try #require(harness.store.pane(parentPane.id)?.drawer?.drawerId)
        harness.store.setActiveDrawerPane(secondDrawerPane.id, in: parentPane.id)
        for paneId in [parentPane.id, firstDrawerPane.id, secondDrawerPane.id] {
            let facets = try #require(
                harness.store.paneAtom.graphAtom.paneState(paneId)?.durableContextFacets
            )
            #expect(facets.repoId == repo.id)
            #expect(facets.worktreeId == worktree.id)
            #expect(facets.cwd?.standardizedFileURL.path == worktree.path.standardizedFileURL.path)
        }

        harness.coordinator.execute(.closeTab(tabId: tab.id))
        harness.coordinator.undoCloseTab()

        let restoredTab = try #require(harness.store.tab(tab.id))
        let restoredParent = try #require(harness.store.pane(parentPane.id))
        let restoredDrawerView = try #require(harness.store.drawerView(forParent: parentPane.id))
        #expect(restoredTab.allPaneIds == [parentPane.id, firstDrawerPane.id, secondDrawerPane.id])
        #expect(restoredParent.drawer?.paneIds == [firstDrawerPane.id, secondDrawerPane.id])
        #expect(restoredDrawerView.layout.paneIds == [firstDrawerPane.id, secondDrawerPane.id])
        #expect(restoredDrawerView.activeChildId == secondDrawerPane.id)
        #expect(harness.store.drawerCursorAtom.isExpanded(drawerId: drawerId))
        #expect(harness.viewRegistry.terminalStatusPlaceholderView(for: parentPane.id)?.mode == .preparing)
        for paneId in [parentPane.id, firstDrawerPane.id, secondDrawerPane.id] {
            let facets = try #require(
                harness.store.paneAtom.graphAtom.paneState(paneId)?.durableContextFacets
            )
            #expect(facets.repoId == repo.id)
            #expect(facets.worktreeId == worktree.id)
            #expect(facets.cwd?.standardizedFileURL.path == worktree.path.standardizedFileURL.path)
        }
    }

    @Test("deferred undo restore persists drawer graph and matched local cursor through fresh SQLite restore")
    func deferredUndoRestore_persistsDrawerStateThroughFreshSQLiteRestore() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-undo-restore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let identityAtom = WorkspaceIdentityAtom(
            workspaceId: workspaceId,
            workspaceName: "Deferred Drawer Restore",
            createdAt: Date(timeIntervalSince1970: 1_700_000_088)
        )
        let sqliteDatastore = try await preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        try fixture.coreRepository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: identityAtom.workspaceName,
                createdAt: identityAtom.createdAt,
                updatedAt: identityAtom.createdAt
            )
        )
        let store = WorkspaceStore(
            identityAtom: identityAtom,
            sqliteDatastore: sqliteDatastore
        )
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: UndoRestoreSurfaceManager(
                createSurfaceResult: .failure(.ghosttyNotInitialized)
            ),
            runtimeRegistry: RuntimeRegistry(),
            windowLifecycleStore: WindowLifecycleAtom(),
            bridgePaneAttendance: BridgePaneAttendanceAtom()
        )
        let (repo, worktree) = makeRepoAndWorktree(store, root: tempDir)
        let topologyStore = RepositoryTopologyStore(
            atom: store.repositoryTopologyAtom,
            sqliteDatastore: sqliteDatastore
        )
        try await topologyStore.flushAsync()
        let parentPane = makeWorktreePane(store, repo: repo, worktree: worktree, title: "Parent")
        let tab = Tab(paneId: parentPane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        let firstDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let secondDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let drawerId = try #require(store.pane(parentPane.id)?.drawer?.drawerId)
        store.setActiveDrawerPane(secondDrawerPane.id, in: parentPane.id)

        coordinator.execute(.closeTab(tabId: tab.id))
        coordinator.undoCloseTab()
        let flushOutcome = await store.flushAsync()

        #expect(flushOutcome.succeeded)
        let restoredStore = WorkspaceStore(
            sqliteDatastore: try await preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        )
        await restoredStore.loadCanonicalComposition()

        let restoredTab = try #require(restoredStore.tab(tab.id))
        let restoredParent = try #require(restoredStore.pane(parentPane.id))
        let restoredDrawerView = try #require(restoredStore.drawerView(forParent: parentPane.id))
        #expect(restoredTab.allPaneIds == [parentPane.id, firstDrawerPane.id, secondDrawerPane.id])
        #expect(restoredParent.drawer?.paneIds == [firstDrawerPane.id, secondDrawerPane.id])
        #expect(restoredDrawerView.layout.paneIds == [firstDrawerPane.id, secondDrawerPane.id])
        #expect(restoredDrawerView.activeChildId == secondDrawerPane.id)
        #expect(restoredStore.drawerCursorAtom.isExpanded(drawerId: drawerId))
    }

    @Test("undoTabClose removes empty tab when all pane restorations fail")
    func undoTabClose_allRestoreFailures_removesTab() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let terminalPane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Terminal")
        let tab = Tab(paneId: terminalPane.id)
        harness.store.appendTab(tab)
        harness.coordinator.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)

        harness.coordinator.execute(.closeTab(tabId: tab.id))
        harness.coordinator.undoCloseTab()

        #expect(harness.store.tab(tab.id) == nil)
        #expect(harness.store.activeTabId == nil)
        #expect(harness.store.pane(terminalPane.id) == nil)
    }

    @Test("undoTabClose restore failure retires a stale rendered slot instead of deleting it")
    func undoTabClose_restoreFailure_retiresStaleRenderedSlot() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let terminalPane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Terminal")
        let tab = Tab(paneId: terminalPane.id)
        harness.store.appendTab(tab)
        let originalSlot = harness.viewRegistry.ensureSlot(for: terminalPane.id)
        harness.viewRegistry.surfaceRenderedIds("tab:\(tab.id)", ids: [terminalPane.id])
        harness.coordinator.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)

        harness.coordinator.execute(.closeTab(tabId: tab.id))
        harness.coordinator.undoCloseTab()

        #expect(harness.store.pane(terminalPane.id) == nil)
        #expect(harness.viewRegistry.isRetiredForTesting(terminalPane.id))
        #expect(harness.viewRegistry.peekSlotForTesting(terminalPane.id) === originalSlot)
    }

    @Test("undoPaneClose deferred drawer restore preserves stale rendered drawer slot")
    func undoPaneClose_deferredRestore_preservesStaleRenderedDrawerSlot() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let parent = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Parent")
        let tab = Tab(paneId: parent.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let child = try #require(harness.store.addDrawerPane(to: parent.id))
        let originalSlot = harness.viewRegistry.ensureSlot(for: child.id)
        harness.viewRegistry.surfaceRenderedIds("drawer:\(parent.id)", ids: [child.id])
        harness.coordinator.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)

        harness.coordinator.execute(.closePane(tabId: tab.id, paneId: child.id))
        harness.coordinator.undoCloseTab()

        #expect(harness.store.pane(child.id) != nil)
        #expect(!harness.viewRegistry.isRetiredForTesting(child.id))
        #expect(harness.viewRegistry.peekSlotForTesting(child.id) === originalSlot)
        #expect(harness.viewRegistry.terminalStatusPlaceholderView(for: child.id)?.mode == .preparing)
    }

    @Test("undoPaneClose hard failure removes failed main pane through explicit cleanup")
    func undoPaneClose_hardFailure_removesFailedMainPane() throws {
        let harness = makeHarness(createSurfaceResult: .failure(.ghosttyNotInitialized))
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let anchor = makeWebviewPane(harness.store, title: "Anchor")
        let terminal = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Terminal")
        let tab = Tab(paneId: anchor.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.insertPane(
            terminal.id,
            inTab: tab.id,
            at: anchor.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        let originalSlot = harness.viewRegistry.ensureSlot(for: terminal.id)
        harness.viewRegistry.surfaceRenderedIds("tab:\(tab.id)", ids: [terminal.id])
        harness.coordinator.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)

        harness.coordinator.execute(.closePane(tabId: tab.id, paneId: terminal.id))
        harness.coordinator.undoCloseTab()

        #expect(harness.store.pane(terminal.id) == nil)
        #expect(harness.store.tab(tab.id)?.paneIds == [anchor.id])
        #expect(harness.viewRegistry.isRetiredForTesting(terminal.id))
        #expect(harness.viewRegistry.peekSlotForTesting(terminal.id) === originalSlot)
    }

    @Test("undoTabClose preserves tab when only active arrangement is emptied")
    func undoTabClose_activeArrangementEmpty_preservesTabViaFallbackArrangement() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let terminalPane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Terminal")
        let webviewPane = makeWebviewPane(harness.store, title: "Web")
        let tab = Tab(paneId: terminalPane.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            webviewPane.id,
            inTab: tab.id,
            at: terminalPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        guard
            let terminalOnlyArrangementId = harness.store.createArrangement(
                name: "Terminal only",
                inTab: tab.id
            )
        else {
            Issue.record("Expected arrangement creation to succeed")
            return
        }
        harness.store.switchArrangement(to: terminalOnlyArrangementId, inTab: tab.id)
        harness.coordinator.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)

        harness.coordinator.execute(.closeTab(tabId: tab.id))
        harness.coordinator.undoCloseTab()

        guard let restoredTab = harness.store.tab(tab.id) else {
            Issue.record("Expected tab to remain after fallback arrangement recovery")
            return
        }
        #expect(restoredTab.panes == [webviewPane.id])
        #expect(!(restoredTab.activeArrangement.layout.paneIds.isEmpty))
        #expect(restoredTab.activeArrangement.layout.contains(webviewPane.id))
    }

    @Test("undoCloseTab skips orphaned drawer-child pane snapshots safely")
    func undoCloseTab_skipsOrphanedDrawerChildSnapshot() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let anchorPane = makeWebviewPane(harness.store, title: "Anchor")
        let parentPane = makeWebviewPane(harness.store, title: "Parent")
        let tab = Tab(paneId: anchorPane.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            parentPane.id,
            inTab: tab.id,
            at: anchorPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )

        guard
            let drawerPane = harness.store.addDrawerPane(
                to: parentPane.id,
                parentFallbackCWD: FileManager.default.homeDirectoryForCurrentUser
            )
        else {
            Issue.record("Expected drawer pane creation")
            return
        }

        harness.coordinator.execute(.closePane(tabId: tab.id, paneId: drawerPane.id))
        #expect(harness.coordinator.undoStack.count == 1)

        harness.store.removePaneFromLayout(parentPane.id, inTab: tab.id)
        harness.store.removePane(parentPane.id)

        harness.coordinator.undoCloseTab()

        #expect(harness.coordinator.undoStack.isEmpty)
        #expect(harness.store.pane(drawerPane.id) == nil)
    }

    @Test("undoTabClose removes tab when all arrangements become empty after restore failures")
    func undoTabClose_allArrangementsEmptyAfterFailures_removesTab() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let terminalPane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Terminal")
        let tab = Tab(paneId: terminalPane.id)
        harness.store.appendTab(tab)
        guard
            let terminalOnlyArrangementId = harness.store.createArrangement(
                name: "Terminal only",
                inTab: tab.id
            )
        else {
            Issue.record("Expected arrangement creation to succeed")
            return
        }
        harness.store.switchArrangement(to: terminalOnlyArrangementId, inTab: tab.id)
        harness.coordinator.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)

        harness.coordinator.execute(.closeTab(tabId: tab.id))
        harness.coordinator.undoCloseTab()

        #expect(harness.store.tab(tab.id) == nil)
    }

    @Test("tab close undo reattaches the retained surface without repository enrichment")
    func tabCloseUndoReattachesRetainedSurfaceWithoutRepositoryEnrichment() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        // Arrange: a floating terminal pane (no worktree/repo) with a mounted view, closed via tab close.
        let pane = harness.store.createPane(launchDirectory: harness.tempDir, provider: .zmx)
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.coordinator.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        let mountedView = TerminalPaneMountView(paneId: pane.id, title: "Terminal")
        harness.coordinator.registerHostedView(mountedView: mountedView, for: pane.id)

        let retainedSurface = ManagedSurface(
            surface: Ghostty.SurfaceView(
                managedSurfaceID: UUIDv7.generate(),
                appCommandDispatcher: NoOpAppCommandDispatcher()
            ),
            metadata: SurfaceMetadata(paneId: pane.id)
        )
        harness.surfaceManager.undoCloseResults = [retainedSurface]

        // Act
        harness.coordinator.execute(.closeTab(tabId: tab.id))
        harness.coordinator.undoCloseTab()

        // Assert: the retained surface is reattached; no fresh surface is created.
        #expect(harness.surfaceManager.attachCalls.map(\.surfaceID) == [retainedSurface.id])
        #expect(harness.surfaceManager.createSurfaceCallCount == 0)
    }

    @Test("pane close undo still reattaches the retained surface")
    func paneCloseUndoStillReattachesRetainedSurface() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        // Arrange: a worktree-bound terminal pane with a mounted view, closed via pane close.
        // Uses the repo's admitted main worktree (not `makeRepoAndWorktree`'s synthetic nested
        // worktree, which reconciles to an unavailable repo and never stamps facets onto the pane).
        let (repo, worktree) = makeAdmittedRepoAndWorktree(harness.store, root: harness.tempDir)
        let anchor = makeWebviewPane(harness.store, title: "Anchor")
        let terminal = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Terminal")
        let tab = Tab(paneId: anchor.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.insertPane(
            terminal.id,
            inTab: tab.id,
            at: anchor.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        harness.coordinator.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        let mountedView = TerminalPaneMountView(paneId: terminal.id, title: "Terminal")
        harness.coordinator.registerHostedView(mountedView: mountedView, for: terminal.id)

        let retainedSurface = ManagedSurface(
            surface: Ghostty.SurfaceView(
                managedSurfaceID: UUIDv7.generate(),
                appCommandDispatcher: NoOpAppCommandDispatcher()
            ),
            metadata: SurfaceMetadata(paneId: terminal.id)
        )
        harness.surfaceManager.undoCloseResults = [retainedSurface]

        // Act
        harness.coordinator.execute(.closePane(tabId: tab.id, paneId: terminal.id))
        harness.coordinator.undoCloseTab()

        // Assert: pane-close undo already reuses the retained surface — pin this today and after the fix.
        #expect(harness.surfaceManager.attachCalls.map(\.surfaceID) == [retainedSurface.id])
        #expect(harness.surfaceManager.createSurfaceCallCount == 0)
    }

    @Test("tab close undo reuses retained surfaces when stack order differs from snapshot order")
    func tabCloseUndoReusesRetainedSurfacesWhenStackOrderDiffersFromSnapshotOrder() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        // Arrange: two floating terminal panes in one tab, each with a mounted view and a
        // retained surface. The mock's retained list is ordered so LIFO popping yields the
        // wrong pane first for the coordinator's reversed snapshot-panes iteration.
        let firstPane = harness.store.createPane(launchDirectory: harness.tempDir, provider: .zmx)
        let secondPane = harness.store.createPane(launchDirectory: harness.tempDir, provider: .zmx)
        let tab = Tab(paneId: firstPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.insertPane(
            secondPane.id,
            inTab: tab.id,
            at: firstPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        harness.coordinator.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        let firstMountedView = TerminalPaneMountView(paneId: firstPane.id, title: "First")
        harness.coordinator.registerHostedView(mountedView: firstMountedView, for: firstPane.id)
        let secondMountedView = TerminalPaneMountView(paneId: secondPane.id, title: "Second")
        harness.coordinator.registerHostedView(mountedView: secondMountedView, for: secondPane.id)

        let retainedFirst = ManagedSurface(
            surface: Ghostty.SurfaceView(
                managedSurfaceID: UUIDv7.generate(),
                appCommandDispatcher: NoOpAppCommandDispatcher()
            ),
            metadata: SurfaceMetadata(paneId: firstPane.id)
        )
        let retainedSecond = ManagedSurface(
            surface: Ghostty.SurfaceView(
                managedSurfaceID: UUIDv7.generate(),
                appCommandDispatcher: NoOpAppCommandDispatcher()
            ),
            metadata: SurfaceMetadata(paneId: secondPane.id)
        )
        // The mock pops LIFO from the end of this array (mirroring SurfaceManager's undo stack).
        // Ordered [retainedSecond, retainedFirst], the first pop yields retainedFirst, which
        // mismatches the coordinator's reversed snapshot.panes iteration (secondPane restores
        // first).
        harness.surfaceManager.undoCloseResults = [retainedSecond, retainedFirst]

        // Act
        harness.coordinator.execute(.closeTab(tabId: tab.id))
        harness.coordinator.undoCloseTab()

        // Assert: both retained surfaces are reused by pane id; no fresh surface is created.
        #expect(harness.surfaceManager.createSurfaceCallCount == 0)
        #expect(
            Set(harness.surfaceManager.attachCalls.map(\.surfaceID))
                == Set([retainedFirst.id, retainedSecond.id])
        )
    }

    @Test("undo without a retained surface falls back to fresh creation")
    func undoWithoutRetainedSurfaceFallsBackToFreshCreation() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        // Arrange: a floating terminal pane with no retained surface available on undo.
        let pane = harness.store.createPane(launchDirectory: harness.tempDir, provider: .zmx)
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.coordinator.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        let mountedView = TerminalPaneMountView(paneId: pane.id, title: "Terminal")
        harness.coordinator.registerHostedView(mountedView: mountedView, for: pane.id)

        // Act
        harness.coordinator.execute(.closeTab(tabId: tab.id))
        harness.coordinator.undoCloseTab()

        // Assert: with no retained surface to pop, restore falls back to fresh surface creation.
        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
    }
}

@MainActor
private final class UndoRestoreSurfaceManager: WorkspaceSurfaceManaging {
    private let createSurfaceResult: Result<ManagedSurface, SurfaceError>
    /// Retained surfaces looked up by pane id via `undoClose(forPaneId:)`, mirroring `SurfaceManager`'s undo stack.
    var undoCloseResults: [ManagedSurface]
    private(set) var attachCalls: [(surfaceID: UUID, paneID: UUID)] = []
    private(set) var createSurfaceCallCount = 0

    init(
        createSurfaceResult: Result<ManagedSurface, SurfaceError>,
        undoCloseResults: [ManagedSurface] = []
    ) {
        self.createSurfaceResult = createSurfaceResult
        self.undoCloseResults = undoCloseResults
    }

    func syncFocus(activeSurfaceId: UUID?) {}

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        createSurfaceCallCount += 1
        return createSurfaceResult
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        attachCalls.append((surfaceID: surfaceId, paneID: paneId))
        return nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {}

    func undoClose(forPaneId paneId: UUID) -> ManagedSurface? {
        guard let index = undoCloseResults.lastIndex(where: { $0.metadata.paneId == paneId }) else {
            return nil
        }
        return undoCloseResults.remove(at: index)
    }

    func destroy(_ surfaceId: UUID) {}
}

/// No-op dispatcher used only to satisfy `Ghostty.SurfaceView`'s bare test initializer.
@MainActor
private final class NoOpAppCommandDispatcher: AppCommandDispatching {
    func dispatch(_: AppCommand) {}
    func dispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) {}
    func canDispatch(_: AppCommand) -> Bool { false }
    func canDispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool { false }
    func bridgePaneCommandTarget(worktreeId _: UUID) -> BridgePaneCommandTarget? { nil }
    func dispatchMovePaneToTab(sourcePaneId _: UUID, sourceTabId _: UUID?, targetTabId _: UUID) {}
}
