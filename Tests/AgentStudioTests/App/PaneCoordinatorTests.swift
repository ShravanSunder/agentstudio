import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneCoordinatorTests {
    private struct PaneCoordinatorHarness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let runtime: SessionRuntime
        let coordinator: PaneCoordinator
        let tempDir: URL
    }

    private func makeHarnessCoordinator() -> PaneCoordinatorHarness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore(persistor: persistor)
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let coordinator = PaneCoordinator(store: store, viewRegistry: viewRegistry, runtime: runtime)
        return PaneCoordinatorHarness(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            coordinator: coordinator,
            tempDir: tempDir
        )
    }

    private func makeWebviewPane(_ store: WorkspaceStore, title: String) -> Pane {
        let url = URL(string: "https://example.com/\(UUID().uuidString)")!
        return store.createPane(
            content: .webview(WebviewState(url: url, showNavigation: true)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: title), title: title)
        )
    }

    @Test
    func test_paneCoordinator_exposesExecuteAPI() async {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let action: PaneAction = .selectTab(tabId: UUID())
        harness.coordinator.execute(action)
    }

    @Test("undo close tab restores the tab and activates it")
    func undoCloseTab_restoresAndActivatesClosedTab() {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let store = harness.store
        let coordinator = harness.coordinator

        let paneA = makeWebviewPane(store, title: "A")
        let paneB = makeWebviewPane(store, title: "B")
        let tabA = Tab(paneId: paneA.id)
        let tabB = Tab(paneId: paneB.id)
        store.appendTab(tabA)
        store.appendTab(tabB)
        store.setActiveTab(tabB.id)

        coordinator.execute(.closeTab(tabId: tabA.id))
        #expect(store.tab(tabA.id) == nil)
        #expect(store.activeTabId == tabB.id)
        #expect(coordinator.undoStack.count == 1)

        coordinator.undoCloseTab()

        #expect(store.tab(tabA.id) != nil)
        #expect(store.activeTabId == tabA.id)
        #expect(coordinator.undoStack.isEmpty)
    }

    @Test("close pane undo round-trips pane in layout")
    func closePane_undo_restoresPane() {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let store = harness.store
        let coordinator = harness.coordinator

        let paneA = makeWebviewPane(store, title: "A")
        let paneB = makeWebviewPane(store, title: "B")
        let tab = Tab(paneId: paneA.id)
        store.appendTab(tab)
        store.insertPane(
            paneB.id,
            inTab: tab.id,
            at: paneA.id,
            direction: .horizontal,
            position: .after
        )

        coordinator.execute(.closePane(tabId: tab.id, paneId: paneB.id))
        guard let afterClose = store.tab(tab.id) else {
            Issue.record("Expected tab to remain after closing one pane")
            return
        }
        #expect(afterClose.paneIds == [paneA.id])
        #expect(coordinator.undoStack.count == 1)

        coordinator.undoCloseTab()
        guard let afterUndo = store.tab(tab.id) else {
            Issue.record("Expected tab to exist after undo")
            return
        }
        #expect(afterUndo.paneIds.count == 2)
        #expect(Set(afterUndo.paneIds) == Set([paneA.id, paneB.id]))
    }

    @Test("close-pane on a single-pane tab canonicalizes to close-tab before coordinator execution")
    func closePane_singlePaneTabCanonicalizesToCloseTab() {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let store = harness.store
        let coordinator = harness.coordinator

        let pane = makeWebviewPane(store, title: "Solo")
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        let snapshot = ActionResolver.snapshot(
            from: store.tabs,
            activeTabId: store.activeTabId,
            isManagementModeActive: false
        )
        let validated = try? ActionValidator.validate(
            .closePane(tabId: tab.id, paneId: pane.id),
            state: snapshot
        ).get()
        guard let validated else {
            Issue.record("Expected closePane to validate")
            return
        }

        coordinator.execute(validated.action)

        #expect(store.tab(tab.id) == nil)
        guard let entry = coordinator.undoStack.last else {
            Issue.record("Expected undo entry after closePane escalation")
            return
        }
        switch entry {
        case .tab(let snapshot):
            #expect(snapshot.tab.id == tab.id)
        case .pane:
            Issue.record("Expected tab snapshot when closing the last pane")
        }
    }

    @Test("closing tab with drawer children snapshots all panes for undo")
    func closeTab_withDrawerChildren_snapshotsUndo() {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let store = harness.store
        let coordinator = harness.coordinator

        let parentPane = makeWebviewPane(store, title: "Parent")
        let tab = Tab(paneId: parentPane.id)
        store.appendTab(tab)
        guard let drawerPane = store.addDrawerPane(to: parentPane.id) else {
            Issue.record("Expected drawer pane creation to succeed")
            return
        }

        coordinator.execute(.closeTab(tabId: tab.id))

        #expect(store.tab(tab.id) == nil)
        #expect(store.tabs.allSatisfy { !$0.paneIds.contains(parentPane.id) })
        #expect(store.tabs.allSatisfy { !$0.paneIds.contains(drawerPane.id) })

        guard case .tab(let snapshot)? = coordinator.undoStack.last else {
            Issue.record("Expected tab close snapshot in undo stack")
            return
        }
        let snapshottedPaneIds = Set(snapshot.panes.map(\.id))
        #expect(snapshottedPaneIds.contains(parentPane.id))
        #expect(snapshottedPaneIds.contains(drawerPane.id))
    }

    @Test("openWebview creates and activates a new tab")
    func openWebview_createsAndActivatesTab() {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let store = harness.store
        let viewRegistry = harness.viewRegistry
        let coordinator = harness.coordinator

        let opened = coordinator.openWebview(url: URL(string: "https://example.com/open-webview-test")!)
        guard let opened else {
            Issue.record("Expected webview pane to open")
            return
        }

        #expect(store.tabs.count == 1)
        #expect(store.activeTabId == store.tabs.first?.id)
        #expect(store.tab(store.tabs[0].id)?.paneIds == [opened.id])
        #expect(viewRegistry.view(for: opened.id) != nil)
    }

    @Test("teardownView unregisters runtime from RuntimeRegistry")
    func teardownViewUnregistersRuntime() {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let runtimePaneId = PaneId()
        let metadata = PaneMetadata(
            paneId: runtimePaneId,
            contentType: .browser,
            source: .floating(workingDirectory: nil, title: "Runtime Teardown"),
            title: "Runtime Teardown"
        )
        let runtime = WebviewRuntime(
            paneId: runtimePaneId,
            metadata: metadata
        )
        runtime.transitionToReady()
        harness.coordinator.registerRuntime(runtime)

        #expect(harness.coordinator.runtimeForPane(runtimePaneId) != nil)
        harness.coordinator.teardownView(for: runtimePaneId.uuid)
        #expect(harness.coordinator.runtimeForPane(runtimePaneId) == nil)
    }

    @Test("focusPane auto-expands minimized pane")
    func focusPane_autoExpandsMinimizedPane() {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let store = harness.store
        let coordinator = harness.coordinator

        let paneA = makeWebviewPane(store, title: "A")
        let paneB = makeWebviewPane(store, title: "B")
        let tab = Tab(paneId: paneA.id)
        store.appendTab(tab)
        store.insertPane(
            paneB.id,
            inTab: tab.id,
            at: paneA.id,
            direction: .horizontal,
            position: .after
        )

        coordinator.execute(.minimizePane(tabId: tab.id, paneId: paneB.id))
        #expect(store.tab(tab.id)?.minimizedPaneIds.contains(paneB.id) == true)

        coordinator.execute(.focusPane(tabId: tab.id, paneId: paneB.id))

        #expect(store.tab(tab.id)?.minimizedPaneIds.contains(paneB.id) == false)
        #expect(store.tab(tab.id)?.activePaneId == paneB.id)
    }

    @Test("undo skips stale pane entries whose tab no longer exists")
    func undo_skipsStalePaneEntryWhenTabMissing() {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let store = harness.store
        let coordinator = harness.coordinator

        let paneA = makeWebviewPane(store, title: "A")
        let paneB = makeWebviewPane(store, title: "B")
        let tab = Tab(paneId: paneA.id)
        store.appendTab(tab)
        store.insertPane(
            paneB.id,
            inTab: tab.id,
            at: paneA.id,
            direction: .horizontal,
            position: .after
        )

        coordinator.execute(.closePane(tabId: tab.id, paneId: paneB.id))
        #expect(coordinator.undoStack.count == 1)

        store.removeTab(tab.id)
        coordinator.undoCloseTab()

        #expect(store.tab(tab.id) == nil)
        #expect(coordinator.undoStack.isEmpty)
    }

    @Test("undo stack keeps only max configured entries")
    func undoStack_capsAtMaxEntries() {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let store = harness.store
        let coordinator = harness.coordinator

        for index in 0..<12 {
            let pane = makeWebviewPane(store, title: "Pane-\(index)")
            let tab = Tab(paneId: pane.id)
            store.appendTab(tab)
            coordinator.execute(.closeTab(tabId: tab.id))
        }

        #expect(coordinator.undoStack.count == 10)
    }

    @Test("syncRootsAndActivity")
    func syncRootsAndActivity() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-sync-roots-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore(persistor: persistor)
        store.restore()

        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/repo-sync-roots-\(UUID().uuidString)"))
        let primaryWorktree = Worktree(
            name: "main",
            path: repo.repoPath,
            branch: "main",
            isMainWorktree: true
        )
        let secondaryWorktree = Worktree(
            name: "feature-a",
            path: repo.repoPath.appending(path: "feature-a"),
            branch: "feature-a"
        )
        store.updateRepoWorktrees(repo.id, worktrees: [primaryWorktree, secondaryWorktree])

        let primaryPane = store.createPane(
            source: .worktree(worktreeId: primaryWorktree.id, repoId: repo.id),
            facets: PaneContextFacets(
                repoId: repo.id,
                worktreeId: primaryWorktree.id,
                cwd: primaryWorktree.path
            )
        )
        let primaryTab = Tab(paneId: primaryPane.id)
        store.appendTab(primaryTab)
        store.setActiveTab(primaryTab.id)

        let filesystemSource = RecordingFilesystemSource()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: MockPaneCoordinatorSurfaceManager(),
            runtimeRegistry: RuntimeRegistry(),
            filesystemSource: filesystemSource,
            paneFilesystemProjectionStore: PaneFilesystemProjectionStore(),
            workspaceGitStatusStore: WorkspaceGitStatusStore()
        )

        await waitUntilFilesystemState(
            source: filesystemSource,
            timeout: .milliseconds(600)
        ) { snapshot in
            Set(snapshot.registeredRoots.keys) == Set([primaryWorktree.id, secondaryWorktree.id])
                && snapshot.activityByWorktreeId[primaryWorktree.id] == true
                && snapshot.activityByWorktreeId[secondaryWorktree.id] == false
                && snapshot.activePaneWorktreeId == primaryWorktree.id
        }

        let tertiaryWorktree = Worktree(
            name: "feature-b",
            path: repo.repoPath.appending(path: "feature-b"),
            branch: "feature-b"
        )
        store.updateRepoWorktrees(repo.id, worktrees: [primaryWorktree, tertiaryWorktree])

        await waitUntilFilesystemState(
            source: filesystemSource,
            timeout: .milliseconds(600)
        ) { snapshot in
            Set(snapshot.registeredRoots.keys) == Set([primaryWorktree.id, tertiaryWorktree.id])
                && snapshot.activityByWorktreeId[primaryWorktree.id] == true
                && snapshot.activityByWorktreeId[tertiaryWorktree.id] == false
                && snapshot.activePaneWorktreeId == primaryWorktree.id
        }

        let tertiaryPane = store.createPane(
            source: .worktree(worktreeId: tertiaryWorktree.id, repoId: repo.id),
            facets: PaneContextFacets(
                repoId: repo.id,
                worktreeId: tertiaryWorktree.id,
                cwd: tertiaryWorktree.path
            )
        )
        let tertiaryTab = Tab(paneId: tertiaryPane.id)
        store.appendTab(tertiaryTab)
        coordinator.execute(.selectTab(tabId: tertiaryTab.id))

        await waitUntilFilesystemState(
            source: filesystemSource,
            timeout: .milliseconds(600)
        ) { snapshot in
            snapshot.activityByWorktreeId[tertiaryWorktree.id] == true
                && snapshot.activePaneWorktreeId == tertiaryWorktree.id
        }

        _ = coordinator
    }

    @Test("filesystem sync converges to latest roots when updates arrive during an in-flight pass")
    func syncRootsAndActivityConvergesUnderInFlightUpdates() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-sync-converge-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore(persistor: persistor)
        store.restore()

        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/repo-sync-converge-\(UUID().uuidString)"))
        let mainWorktree = Worktree(
            name: "main",
            path: repo.repoPath,
            branch: "main",
            isMainWorktree: true
        )
        let staleWorktree = Worktree(
            name: "stale-branch",
            path: repo.repoPath.appending(path: "stale-branch"),
            branch: "stale-branch"
        )
        store.updateRepoWorktrees(repo.id, worktrees: [mainWorktree, staleWorktree])

        let primaryPane = store.createPane(
            source: .worktree(worktreeId: mainWorktree.id, repoId: repo.id),
            facets: PaneContextFacets(
                repoId: repo.id,
                worktreeId: mainWorktree.id,
                cwd: mainWorktree.path
            )
        )
        let primaryTab = Tab(paneId: primaryPane.id)
        store.appendTab(primaryTab)
        store.setActiveTab(primaryTab.id)

        let filesystemSource = DelayingRecordingFilesystemSource(operationDelay: .milliseconds(40))
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: MockPaneCoordinatorSurfaceManager(),
            runtimeRegistry: RuntimeRegistry(),
            filesystemSource: filesystemSource,
            paneFilesystemProjectionStore: PaneFilesystemProjectionStore(),
            workspaceGitStatusStore: WorkspaceGitStatusStore()
        )
        _ = coordinator

        // Trigger a second desired state while the initial sync pass is still executing.
        let latestWorktree = Worktree(
            name: "latest-branch",
            path: repo.repoPath.appending(path: "latest-branch"),
            branch: "latest-branch"
        )
        store.updateRepoWorktrees(repo.id, worktrees: [mainWorktree, latestWorktree])

        await waitUntilFilesystemState(
            source: filesystemSource,
            timeout: .seconds(2)
        ) { snapshot in
            Set(snapshot.registeredRoots.keys) == Set([mainWorktree.id, latestWorktree.id])
                && snapshot.registeredRoots[staleWorktree.id] == nil
                && snapshot.activityByWorktreeId[mainWorktree.id] == true
                && snapshot.activityByWorktreeId[latestWorktree.id] == false
                && snapshot.activePaneWorktreeId == mainWorktree.id
        }
    }

    private func waitUntilFilesystemState(
        source: RecordingFilesystemSource,
        timeout: Duration,
        condition: @escaping @Sendable (FilesystemSourceSnapshot) -> Bool
    ) async {
        let deadline = ContinuousClock().now.advanced(by: timeout)
        while ContinuousClock().now < deadline {
            let snapshot = await source.snapshot()
            if condition(snapshot) {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let finalSnapshot = await source.snapshot()
        Issue.record("Timed out waiting for filesystem sync state. Snapshot: \(String(describing: finalSnapshot))")
    }

    private func waitUntilFilesystemState(
        source: DelayingRecordingFilesystemSource,
        timeout: Duration,
        condition: @escaping @Sendable (FilesystemSourceSnapshot) -> Bool
    ) async {
        let deadline = ContinuousClock().now.advanced(by: timeout)
        while ContinuousClock().now < deadline {
            let snapshot = await source.snapshot()
            if condition(snapshot) {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let finalSnapshot = await source.snapshot()
        Issue.record(
            "Timed out waiting for delayed filesystem sync state. Snapshot: \(String(describing: finalSnapshot))")
    }
}

private struct FilesystemSourceSnapshot: Sendable, CustomStringConvertible {
    let registeredRoots: [UUID: URL]
    let activityByWorktreeId: [UUID: Bool]
    let activePaneWorktreeId: UUID?

    var description: String {
        "registered=\(registeredRoots.keys.map(\.uuidString).sorted()) "
            + "activity=\(activityByWorktreeId.mapValues { $0 ? "active" : "idle" }) "
            + "activePaneWorktree=\(activePaneWorktreeId?.uuidString ?? "nil")"
    }
}

private actor RecordingFilesystemSource: PaneCoordinatorFilesystemSourceManaging {
    private(set) var registeredRoots: [UUID: URL] = [:]
    private(set) var activityByWorktreeId: [UUID: Bool] = [:]
    private(set) var activePaneWorktreeId: UUID?

    func register(worktreeId: UUID, rootPath: URL) {
        registeredRoots[worktreeId] = rootPath
    }

    func unregister(worktreeId: UUID) {
        registeredRoots.removeValue(forKey: worktreeId)
        activityByWorktreeId.removeValue(forKey: worktreeId)
        if activePaneWorktreeId == worktreeId {
            activePaneWorktreeId = nil
        }
    }

    func setActivity(worktreeId: UUID, isActiveInApp: Bool) {
        activityByWorktreeId[worktreeId] = isActiveInApp
    }

    func setActivePaneWorktree(worktreeId: UUID?) {
        activePaneWorktreeId = worktreeId
    }

    func snapshot() -> FilesystemSourceSnapshot {
        FilesystemSourceSnapshot(
            registeredRoots: registeredRoots,
            activityByWorktreeId: activityByWorktreeId,
            activePaneWorktreeId: activePaneWorktreeId
        )
    }
}

private actor DelayingRecordingFilesystemSource: PaneCoordinatorFilesystemSourceManaging {
    private let operationDelay: Duration
    private(set) var registeredRoots: [UUID: URL] = [:]
    private(set) var activityByWorktreeId: [UUID: Bool] = [:]
    private(set) var activePaneWorktreeId: UUID?

    init(operationDelay: Duration) {
        self.operationDelay = operationDelay
    }

    func register(worktreeId: UUID, rootPath: URL) async {
        try? await Task.sleep(for: operationDelay)
        registeredRoots[worktreeId] = rootPath
    }

    func unregister(worktreeId: UUID) async {
        try? await Task.sleep(for: operationDelay)
        registeredRoots.removeValue(forKey: worktreeId)
        activityByWorktreeId.removeValue(forKey: worktreeId)
        if activePaneWorktreeId == worktreeId {
            activePaneWorktreeId = nil
        }
    }

    func setActivity(worktreeId: UUID, isActiveInApp: Bool) async {
        try? await Task.sleep(for: operationDelay)
        activityByWorktreeId[worktreeId] = isActiveInApp
    }

    func setActivePaneWorktree(worktreeId: UUID?) async {
        try? await Task.sleep(for: operationDelay)
        activePaneWorktreeId = worktreeId
    }

    func snapshot() -> FilesystemSourceSnapshot {
        FilesystemSourceSnapshot(
            registeredRoots: registeredRoots,
            activityByWorktreeId: activityByWorktreeId,
            activePaneWorktreeId: activePaneWorktreeId
        )
    }
}

private final class MockPaneCoordinatorSurfaceManager: PaneCoordinatorSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>

    init() {
        self.cwdStream = AsyncStream { continuation in
            continuation.onTermination = { _ in }
        }
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> {
        cwdStream
    }

    func syncFocus(activeSurfaceId _: UUID?) {}

    func createSurface(
        config _: Ghostty.SurfaceConfiguration,
        metadata _: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        .failure(.operationFailed("mock"))
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        _ = surfaceId
        _ = paneId
        return nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {
        _ = surfaceId
        _ = reason
    }

    func undoClose() -> ManagedSurface? { nil }

    func requeueUndo(_ surfaceId: UUID) {
        _ = surfaceId
    }

    func destroy(_ surfaceId: UUID) {
        _ = surfaceId
    }
}
