import AppKit
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceSurfaceCoordinatorUndoRestoreTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private let trustedBounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    private struct Harness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let runtime: SessionRuntime
        let coordinator: WorkspaceSurfaceCoordinator
        let tempDir: URL
    }

    private func makeHarness(
        createSurfaceResult: Result<ManagedSurface, SurfaceError> = .failure(.ghosttyNotInitialized)
    ) -> Harness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-undo-restore-\(UUID().uuidString)")
        let store = WorkspaceStore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: UndoRestoreSurfaceManager(createSurfaceResult: createSurfaceResult),
            runtimeRegistry: RuntimeRegistry(),
            windowLifecycleStore: WindowLifecycleAtom()
        )
        return Harness(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            coordinator: coordinator,
            tempDir: tempDir
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
        return (repo, worktree)
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
        try fixture.coreRepository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: identityAtom.workspaceName,
                createdAt: identityAtom.createdAt,
                updatedAt: identityAtom.createdAt
            )
        )
        let sqliteDatastore = workspaceSQLiteDatastore(from: fixture.backend)
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
            windowLifecycleStore: WindowLifecycleAtom()
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
            sqliteDatastore: workspaceSQLiteDatastore(from: fixture.backend)
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

        guard let drawerPane = harness.store.addDrawerPane(to: parentPane.id) else {
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
}

@MainActor
private final class UndoRestoreSurfaceManager: WorkspaceSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>
    private let createSurfaceResult: Result<ManagedSurface, SurfaceError>

    init(createSurfaceResult: Result<ManagedSurface, SurfaceError>) {
        self.createSurfaceResult = createSurfaceResult
        self.cwdStream = AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { continuation in
            continuation.finish()
        }
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { cwdStream }

    func syncFocus(activeSurfaceId: UUID?) {}

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        createSurfaceResult
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? {
        nil
    }

    func requeueUndo(_ surfaceId: UUID) {}

    func destroy(_ surfaceId: UUID) {}
}
