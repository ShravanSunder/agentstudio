import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneCoordinatorHardeningTests {
    private struct Harness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let runtime: SessionRuntime
        let coordinator: PaneCoordinator
        let surfaceManager: MockPaneCoordinatorSurfaceManager
        let tempDir: URL
    }

    private func makeHarness(
        createSurfaceResult: Result<ManagedSurface, SurfaceError> = .failure(.ghosttyNotInitialized)
    ) -> Harness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-hardening-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let surfaceManager = MockPaneCoordinatorSurfaceManager(createSurfaceResult: createSurfaceResult)
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: surfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )
        return Harness(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            coordinator: coordinator,
            surfaceManager: surfaceManager,
            tempDir: tempDir
        )
    }

    private func makeRepoAndWorktree(_ store: WorkspaceStore, root: URL) -> (Repo, Worktree) {
        let repoPath = root.appending(path: "repo-\(UUID().uuidString)")
        let worktreePath = repoPath.appending(path: "wt-main")
        try? FileManager.default.createDirectory(at: repoPath, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: worktreePath, withIntermediateDirectories: true)

        let repo = store.addRepo(at: repoPath)
        let worktree = Worktree(name: "wt-main", path: worktreePath, branch: "main")
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        return (repo, worktree)
    }

    private func makeWebviewPane(_ store: WorkspaceStore, title: String) -> Pane {
        let url = URL(string: "https://example.com/\(UUID().uuidString)")!
        return store.createPane(
            content: .webview(WebviewState(url: url, showNavigation: true)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: title), title: title)
        )
    }

    private func makeWorktreePane(
        _ store: WorkspaceStore,
        repo: Repo,
        worktree: Worktree,
        title: String
    ) -> Pane {
        store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            title: title,
            provider: .zmx
        )
    }

    @Test("openTerminal rolls back pane and tab state when surface creation fails")
    func openTerminal_rollsBackOnSurfaceCreationFailure() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        guard let persistedRepo = harness.store.repo(repo.id) else {
            Issue.record("Expected repo to be persisted in WorkspaceStore")
            return
        }

        let openedPane = harness.coordinator.openTerminal(for: worktree, in: persistedRepo)

        #expect(openedPane == nil)
        #expect(harness.store.tabs.isEmpty)
        #expect(harness.store.panes.isEmpty)
        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
    }

    @Test("closeTab tears down views for panes hidden by non-active arrangements")
    func closeTab_tearsDownAllOwnedPaneViews() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let paneA = makeWebviewPane(harness.store, title: "A")
        let paneB = makeWebviewPane(harness.store, title: "B")
        let paneC = makeWebviewPane(harness.store, title: "C")
        let tab = Tab(paneId: paneA.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            paneB.id,
            inTab: tab.id,
            at: paneA.id,
            direction: .horizontal,
            position: .after
        )
        harness.store.insertPane(
            paneC.id,
            inTab: tab.id,
            at: paneB.id,
            direction: .horizontal,
            position: .after
        )
        guard
            let focusArrangementId = harness.store.createArrangement(
                name: "Focus AB",
                paneIds: Set([paneA.id, paneB.id]),
                inTab: tab.id
            )
        else {
            Issue.record("Expected arrangement creation to succeed")
            return
        }
        harness.store.switchArrangement(to: focusArrangementId, inTab: tab.id)

        harness.viewRegistry.register(PaneView(paneId: paneA.id), for: paneA.id)
        harness.viewRegistry.register(PaneView(paneId: paneB.id), for: paneB.id)
        harness.viewRegistry.register(PaneView(paneId: paneC.id), for: paneC.id)

        harness.coordinator.execute(.closeTab(tabId: tab.id))

        #expect(harness.store.tab(tab.id) == nil)
        #expect(harness.viewRegistry.registeredPaneIds.isEmpty)
        guard case .tab(let snapshot)? = harness.coordinator.undoStack.last else {
            Issue.record("Expected tab snapshot in undo stack")
            return
        }
        #expect(Set(snapshot.panes.map(\.id)) == Set([paneA.id, paneB.id, paneC.id]))
    }

    @Test("purgeOrphanedPane only purges panes that are backgrounded")
    func purgeOrphanedPane_requiresBackgroundedResidency() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = makeWebviewPane(harness.store, title: "Transient")
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.viewRegistry.register(PaneView(paneId: pane.id), for: pane.id)

        harness.coordinator.execute(.purgeOrphanedPane(paneId: pane.id))
        #expect(harness.store.pane(pane.id) != nil)
        #expect(harness.viewRegistry.view(for: pane.id) != nil)

        harness.coordinator.execute(.backgroundPane(paneId: pane.id))
        harness.coordinator.execute(.purgeOrphanedPane(paneId: pane.id))
        #expect(harness.store.pane(pane.id) == nil)
        #expect(harness.viewRegistry.view(for: pane.id) == nil)
    }

    @Test("insertPane newTerminal rolls back transient pane when terminal view creation fails")
    func insertPaneNewTerminal_rollsBackOnSurfaceCreationFailure() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let targetPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            title: "Target",
            provider: .zmx
        )
        let tab = Tab(paneId: targetPane.id)
        harness.store.appendTab(tab)
        let initialPaneIds = Set(harness.store.panes.keys)

        harness.coordinator.execute(
            .insertPane(
                source: .newTerminal,
                targetTabId: tab.id,
                targetPaneId: targetPane.id,
                direction: .right
            )
        )

        #expect(Set(harness.store.panes.keys) == initialPaneIds)
        #expect(harness.store.tab(tab.id)?.paneIds == [targetPane.id])
        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
    }

    @Test("reactivatePane re-backgrounds pane if view creation fails")
    func reactivatePane_rollsBackWhenViewCreationFails() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let targetPane = makeWebviewPane(harness.store, title: "Target")
        let tab = Tab(paneId: targetPane.id)
        harness.store.appendTab(tab)

        let backgroundPane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Background")
        harness.store.setResidency(.backgrounded, for: backgroundPane.id)

        harness.coordinator.execute(
            .reactivatePane(
                paneId: backgroundPane.id,
                targetTabId: tab.id,
                targetPaneId: targetPane.id,
                direction: .right
            )
        )

        #expect(harness.store.pane(backgroundPane.id)?.residency == .backgrounded)
        #expect(!(harness.store.tab(tab.id)?.paneIds.contains(backgroundPane.id) ?? false))
    }

    @Test("addDrawerPane rolls back store changes when view creation fails")
    func addDrawerPane_rollsBackOnViewCreationFailure() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let parentPane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Parent")
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)

        let paneIdsBefore = Set(harness.store.panes.keys)
        harness.coordinator.execute(.addDrawerPane(parentPaneId: parentPane.id))

        #expect(Set(harness.store.panes.keys) == paneIdsBefore)
        #expect(harness.store.pane(parentPane.id)?.drawer?.paneIds.isEmpty == true)
    }

    @Test("insertDrawerPane rolls back store changes when view creation fails")
    func insertDrawerPane_rollsBackOnViewCreationFailure() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let parentPane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Parent")
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        guard let existingDrawerPane = harness.store.addDrawerPane(to: parentPane.id) else {
            Issue.record("Expected initial drawer pane creation")
            return
        }

        let paneIdsBefore = Set(harness.store.panes.keys)
        harness.coordinator.execute(
            .insertDrawerPane(
                parentPaneId: parentPane.id,
                targetDrawerPaneId: existingDrawerPane.id,
                direction: .right
            )
        )

        #expect(Set(harness.store.panes.keys) == paneIdsBefore)
        #expect(harness.store.pane(parentPane.id)?.drawer?.paneIds == [existingDrawerPane.id])
    }

    @Test("repair recreateSurface does not bump viewRevision when view recreation fails")
    func repairRecreateSurface_doesNotBumpRevisionOnFailure() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let pane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Repair")
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        let revisionBefore = harness.store.viewRevision

        harness.coordinator.execute(.repair(.recreateSurface(paneId: pane.id)))

        #expect(harness.store.viewRevision == revisionBefore)
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
            position: .after
        )

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

    @Test("undoTabClose removes empty tab when all pane restorations fail")
    func undoTabClose_allRestoreFailures_removesTab() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let terminalPane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Terminal")
        let tab = Tab(paneId: terminalPane.id)
        harness.store.appendTab(tab)

        harness.coordinator.execute(.closeTab(tabId: tab.id))
        harness.coordinator.undoCloseTab()

        #expect(harness.store.tab(tab.id) == nil)
        #expect(harness.store.activeTabId == nil)
        #expect(harness.store.pane(terminalPane.id) == nil)
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
            position: .after
        )
        guard
            let terminalOnlyArrangementId = harness.store.createArrangement(
                name: "Terminal only",
                paneIds: Set([terminalPane.id]),
                inTab: tab.id
            )
        else {
            Issue.record("Expected arrangement creation to succeed")
            return
        }
        harness.store.switchArrangement(to: terminalOnlyArrangementId, inTab: tab.id)

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
            position: .after
        )

        guard let drawerPane = harness.store.addDrawerPane(to: parentPane.id) else {
            Issue.record("Expected drawer pane creation")
            return
        }

        harness.coordinator.execute(.closePane(tabId: tab.id, paneId: drawerPane.id))
        #expect(harness.coordinator.undoStack.count == 1)

        _ = harness.store.removePaneFromLayout(parentPane.id, inTab: tab.id)
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
                paneIds: Set([terminalPane.id]),
                inTab: tab.id
            )
        else {
            Issue.record("Expected arrangement creation to succeed")
            return
        }
        harness.store.switchArrangement(to: terminalOnlyArrangementId, inTab: tab.id)

        harness.coordinator.execute(.closeTab(tabId: tab.id))
        harness.coordinator.undoCloseTab()

        #expect(harness.store.tab(tab.id) == nil)
    }

    @Test("undo GC removes orphaned panes after stack overflows max entries")
    func undoGc_removesExpiredPaneResources() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        var closedPaneIds: [UUID] = []
        for index in 0...(harness.coordinator.maxUndoStackSize) {
            let pane = makeWebviewPane(harness.store, title: "Pane \(index)")
            let tab = Tab(paneId: pane.id)
            harness.store.appendTab(tab)
            harness.coordinator.execute(.closeTab(tabId: tab.id))
            closedPaneIds.append(pane.id)
        }

        #expect(harness.coordinator.undoStack.count == harness.coordinator.maxUndoStackSize)
        guard let oldestClosedPaneId = closedPaneIds.first else {
            Issue.record("Expected at least one closed pane id")
            return
        }
        #expect(harness.store.pane(oldestClosedPaneId) == nil)
    }

    @Test("restoreView registers runtime before undo lookup and rolls back runtime when restore fails")
    func restoreView_registersRuntimeBeforeUndoLookup() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let pane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Restore")
        let runtimePaneId = PaneId(uuid: pane.id)

        var runtimeWasRegisteredDuringUndoLookup = false
        harness.surfaceManager.onUndoClose = {
            runtimeWasRegisteredDuringUndoLookup = harness.coordinator.runtimeForPane(runtimePaneId) != nil
        }

        let restored = harness.coordinator.restoreView(for: pane, worktree: worktree, repo: repo)

        #expect(restored == nil)
        #expect(runtimeWasRegisteredDuringUndoLookup)
        #expect(harness.coordinator.runtimeForPane(runtimePaneId) == nil)
    }
}

@MainActor
private final class MockPaneCoordinatorSurfaceManager: PaneCoordinatorSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>
    private let createSurfaceResult: Result<ManagedSurface, SurfaceError>

    private(set) var createSurfaceCallCount = 0
    var onUndoClose: (() -> Void)?
    var undoCloseResult: ManagedSurface?

    init(
        createSurfaceResult: Result<ManagedSurface, SurfaceError>,
        undoCloseResult: ManagedSurface? = nil,
        onUndoClose: (() -> Void)? = nil
    ) {
        self.createSurfaceResult = createSurfaceResult
        self.undoCloseResult = undoCloseResult
        self.onUndoClose = onUndoClose
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
        createSurfaceCallCount += 1
        return createSurfaceResult
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? {
        onUndoClose?()
        return undoCloseResult
    }

    func requeueUndo(_ surfaceId: UUID) {}

    func destroy(_ surfaceId: UUID) {}
}
