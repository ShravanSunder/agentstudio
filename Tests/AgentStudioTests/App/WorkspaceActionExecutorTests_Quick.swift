import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceActionExecutorTestsQuick {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private struct WorkspaceActionExecutorHarness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let runtime: SessionRuntime
        let coordinator: WorkspaceSurfaceCoordinator
        let executor: WorkspaceActionExecutor
        let tempDir: URL
    }

    private func makeHarness() -> WorkspaceActionExecutorHarness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-action-executor-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore(persistor: persistor)
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            windowLifecycleStore: WindowLifecycleAtom()
        )
        let executor = WorkspaceActionExecutor(coordinator: coordinator, store: store)
        return WorkspaceActionExecutorHarness(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            coordinator: coordinator,
            executor: executor,
            tempDir: tempDir
        )
    }

    @Test("openWebview creates a generic GitHub tab without workspace association")
    func openWebview_addsGenericGitHubTabAndRegistersView() {
        let harness = makeHarness()
        let store = harness.store
        let viewRegistry = harness.viewRegistry
        let executor = harness.executor
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pane = executor.openWebview()

        #expect(pane != nil)
        #expect(store.tabs.count == 1)
        #expect(store.activeTabId == store.tabs[0].id)
        #expect(viewRegistry.view(for: pane!.id) != nil)
        #expect(viewRegistry.webviewView(for: pane!.id) != nil)
        #expect(pane?.webviewState?.url == URL(string: "https://github.com"))
        #expect(pane?.repoId == nil)
        #expect(pane?.worktreeId == nil)
        #expect(pane?.metadata.cwd == nil)
    }

    @Test("openBridgeReview without a worktree context does not create a blank Bridge tab")
    func openBridgeReview_withoutWorktreeContextDoesNotCreateBlankBridgeTab() {
        let harness = makeHarness()
        let store = harness.store
        let viewRegistry = harness.viewRegistry
        let executor = harness.executor
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pane = executor.openBridgeReview()

        #expect(pane == nil)
        #expect(store.tabs.isEmpty)
        #expect(store.activeTabId == nil)
        #expect(viewRegistry.allBridgeViews.isEmpty)
    }

    @Test("openBridgeReview inherits active pane worktree context")
    func openBridgeReview_inheritsActivePaneWorktreeContext() {
        let harness = makeHarness()
        let store = harness.store
        let executor = harness.executor
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let repo = store.addRepo(at: tempDir.appending(path: "repo"))
        guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
            Issue.record("Expected main worktree")
            return
        }
        let sourcePane = store.createPane(
            launchDirectory: worktree.path,
            title: "Source",
            facets: PaneContextFacets(
                repoId: repo.id,
                repoName: repo.name,
                worktreeId: worktree.id,
                worktreeName: worktree.name,
                cwd: worktree.path
            )
        )
        let tab = Tab(paneId: sourcePane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let pane = executor.openBridgeReview()

        #expect(pane != nil)
        #expect(store.tabs.count == 2)
        #expect(store.activeTabId == store.tabs[1].id)
        #expect(pane?.repoId == repo.id)
        #expect(pane?.worktreeId == worktree.id)
        #expect(pane?.metadata.cwd == worktree.path)
        guard case .bridgePanel(let state) = pane?.content,
            case .workspace(let rootPath, let baseline) = state.source
        else {
            Issue.record("Expected Bridge workspace source")
            return
        }
        #expect(rootPath == worktree.path.path)
        #expect(baseline == .localDefaultBranch(branchName: "main"))
    }

    @Test("openBridgeReview falls back to the only registered worktree when no pane has context")
    func openBridgeReview_usesOnlyRegisteredWorktreeWithoutActivePaneContext() {
        let harness = makeHarness()
        let store = harness.store
        let viewRegistry = harness.viewRegistry
        let executor = harness.executor
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let repo = store.addRepo(at: tempDir.appending(path: "repo"))
        guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
            Issue.record("Expected main worktree")
            return
        }

        let pane = executor.openBridgeReview()

        #expect(pane != nil)
        #expect(pane?.repoId == repo.id)
        #expect(pane?.worktreeId == worktree.id)
        #expect(pane?.metadata.cwd == worktree.path)
        let bridgeView = viewRegistry.view(for: pane!.id)?.mountedContentViewForTesting as? BridgePaneMountView
        #expect(bridgeView?.controller.runtime.metadata.worktreeId == worktree.id)
        #expect(bridgeView?.controller.runtime.metadata.repoId == repo.id)
        #expect(bridgeView?.controller.runtime.metadata.cwd == worktree.path)
        guard case .bridgePanel(let state) = pane?.content,
            case .workspace(let rootPath, let baseline) = state.source
        else {
            Issue.record("Expected Bridge workspace source")
            return
        }
        #expect(rootPath == worktree.path.path)
        #expect(baseline == .localDefaultBranch(branchName: "main"))
    }

    @Test("openBridgeReview can target a registered worktree without an active source pane")
    func openBridgeReview_targetsRegisteredWorktree() {
        let harness = makeHarness()
        let store = harness.store
        let viewRegistry = harness.viewRegistry
        let executor = harness.executor
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let repo = store.addRepo(at: tempDir.appending(path: "repo"))
        guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
            Issue.record("Expected main worktree")
            return
        }

        let pane = executor.openBridgeReview(worktreeId: worktree.id)

        #expect(pane != nil)
        #expect(store.tabs.count == 1)
        #expect(store.activeTabId == store.tabs[0].id)
        #expect(pane?.repoId == repo.id)
        #expect(pane?.worktreeId == worktree.id)
        #expect(pane?.metadata.cwd == worktree.path)
        let bridgeView = viewRegistry.view(for: pane!.id)?.mountedContentViewForTesting as? BridgePaneMountView
        #expect(bridgeView?.controller.runtime.metadata.worktreeId == worktree.id)
        #expect(bridgeView?.controller.runtime.metadata.repoId == repo.id)
        #expect(bridgeView?.controller.runtime.metadata.cwd == worktree.path)
        guard case .bridgePanel(let state) = pane?.content,
            case .workspace(let rootPath, let baseline) = state.source
        else {
            Issue.record("Expected Bridge workspace source")
            return
        }
        #expect(rootPath == worktree.path.path)
        #expect(baseline == .localDefaultBranch(branchName: "main"))
    }

    @Test("openBridgeFileView can target a registered worktree without an active source pane")
    func openBridgeFileView_targetsRegisteredWorktree() {
        let harness = makeHarness()
        let store = harness.store
        let viewRegistry = harness.viewRegistry
        let executor = harness.executor
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let repo = store.addRepo(at: tempDir.appending(path: "repo"))
        guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
            Issue.record("Expected main worktree")
            return
        }

        let pane = executor.openBridgeFileView(worktreeId: worktree.id)

        #expect(pane != nil)
        #expect(store.tabs.count == 1)
        #expect(store.activeTabId == store.tabs[0].id)
        #expect(pane?.repoId == repo.id)
        #expect(pane?.worktreeId == worktree.id)
        #expect(pane?.metadata.cwd == worktree.path)
        #expect(pane?.metadata.title == "Files")
        let bridgeView = viewRegistry.view(for: pane!.id)?.mountedContentViewForTesting as? BridgePaneMountView
        #expect(bridgeView?.controller.runtime.metadata.worktreeId == worktree.id)
        #expect(bridgeView?.controller.runtime.metadata.repoId == repo.id)
        #expect(bridgeView?.controller.runtime.metadata.cwd == worktree.path)
        guard case .bridgePanel(let state) = pane?.content,
            state.panelKind == .fileViewer,
            case .workspace(let rootPath, let baseline) = state.source
        else {
            Issue.record("Expected Bridge file-viewer workspace source")
            return
        }
        #expect(rootPath == worktree.path.path)
        #expect(baseline == .localDefaultBranch(branchName: "main"))
    }

    @Test("openBridgeFileView inherits active pane worktree context")
    func openBridgeFileView_inheritsActivePaneWorktreeContext() throws {
        let harness = makeHarness()
        let store = harness.store
        let viewRegistry = harness.viewRegistry
        let executor = harness.executor
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let repo = store.addRepo(at: tempDir.appending(path: "repo"))
        let worktree = try #require(
            store.repos.first(where: { $0.id == repo.id })?.worktrees.first,
            "Expected main worktree"
        )
        let sourcePane = store.createPane(
            launchDirectory: worktree.path,
            title: "Source",
            facets: PaneContextFacets(
                repoId: repo.id,
                repoName: repo.name,
                worktreeId: worktree.id,
                worktreeName: worktree.name,
                cwd: worktree.path
            )
        )
        let tab = Tab(paneId: sourcePane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let pane = try #require(executor.openBridgeFileView())

        #expect(store.tabs.count == 2)
        #expect(store.activeTabId == store.tabs[1].id)
        assertFileViewPane(
            pane,
            repo: repo,
            worktree: worktree,
            viewRegistry: viewRegistry
        )
    }

    @Test("openBridgeFileView falls back to the only registered worktree when no pane has context")
    func openBridgeFileView_usesOnlyRegisteredWorktreeWithoutActivePaneContext() throws {
        let harness = makeHarness()
        let store = harness.store
        let viewRegistry = harness.viewRegistry
        let executor = harness.executor
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let repo = store.addRepo(at: tempDir.appending(path: "repo"))
        let worktree = try #require(
            store.repos.first(where: { $0.id == repo.id })?.worktrees.first,
            "Expected main worktree"
        )

        let pane = try #require(executor.openBridgeFileView())

        assertFileViewPane(
            pane,
            repo: repo,
            worktree: worktree,
            viewRegistry: viewRegistry
        )
    }

    @Test("openBridgeFileView keeps source identity out of the page bootstrap")
    func openBridgeFileView_keepsSourceIdentityOutOfPageBootstrap() throws {
        let harness = makeHarness()
        let store = harness.store
        let viewRegistry = harness.viewRegistry
        let executor = harness.executor
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let repo = store.addRepo(at: tempDir.appending(path: "repo"))
        let worktree = try #require(
            store.repos.first(where: { $0.id == repo.id })?.worktrees.first,
            "Expected main worktree"
        )

        let pane = try #require(executor.openBridgeFileView(worktreeId: worktree.id))
        let bridgeView = try #require(
            viewRegistry.view(for: pane.id)?.mountedContentViewForTesting as? BridgePaneMountView,
            "Expected mounted Bridge file-viewer view"
        )
        let script = bridgeView.controller.bootstrapScriptSourceForTesting

        #expect(script.contains("const APP_PROTOCOL = \"worktree-file\""))
        #expect(script.contains("data-bridge-app-protocol"))
        #expect(!script.contains("data-bridge-worktree-file-source-spec"))
        #expect(!script.contains(repo.id.uuidString))
        #expect(!script.contains(worktree.id.uuidString))
        #expect(!script.contains(StableKey.fromPath(worktree.path)))
    }

    @Test("openContextualWebviewInPane creates a split browser pane with inherited workspace association")
    func openContextualWebviewInPane_addsSplitPaneWithAssociation() {
        let harness = makeHarness()
        let store = harness.store
        let executor = harness.executor
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let repo = store.addRepo(at: tempDir.appending(path: "repo"))
        guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
            Issue.record("Expected main worktree")
            return
        }

        let sourcePane = store.createPane(
            launchDirectory: worktree.path,
            title: "Source",
            facets: PaneContextFacets(
                repoId: repo.id,
                repoName: repo.name,
                worktreeId: worktree.id,
                worktreeName: worktree.name,
                cwd: worktree.path
            )
        )
        let tab = Tab(paneId: sourcePane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let pane = executor.openContextualWebviewInPane(
            sourcePaneId: sourcePane.id,
            targetTabId: tab.id,
            url: URL(string: "https://github.com/ShravanSunder/agentstudio/pulls")!
        )

        #expect(pane != nil)
        #expect(store.tab(tab.id)?.paneIds.count == 2)
        #expect(store.tab(tab.id)?.activePaneId == pane?.id)
        #expect(pane?.webviewState?.url == URL(string: "https://github.com/ShravanSunder/agentstudio/pulls"))
        #expect(pane?.repoId == repo.id)
        #expect(pane?.worktreeId == worktree.id)
        #expect(pane?.metadata.cwd == worktree.path)
    }

    @Test("repair recreateSurface replaces a missing webview view")
    func repair_recreateSurface_recreatesWebviewView() {
        let harness = makeHarness()
        let store = harness.store
        let viewRegistry = harness.viewRegistry
        let coordinator = harness.coordinator
        let executor = harness.executor
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "about:blank")!)),
            metadata: PaneMetadata()
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        _ = coordinator.createViewForContent(pane: pane)
        guard let beforeView = viewRegistry.view(for: pane.id) else {
            Issue.record("Expected webview view to exist before repair")
            return
        }

        viewRegistry.unregister(pane.id)

        executor.execute(.repair(.recreateSurface(paneId: pane.id)))

        let afterView = viewRegistry.view(for: pane.id)
        #expect(afterView != nil)
        #expect(afterView !== beforeView)
    }

    @Test("minimizePane hides pane and expandPane restores active pane")
    func minimize_then_expandPane_updatesTransientState() {
        let harness = makeHarness()
        let store = harness.store
        let executor = harness.executor
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let paneOne = store.createPane()
        let paneTwo = store.createPane()
        let tab = Tab(paneId: paneOne.id)
        store.appendTab(tab)
        store.insertPane(
            paneTwo.id,
            inTab: tab.id,
            at: paneOne.id,
            direction: .horizontal,
            position: .after, sizingMode: .halveTarget
        )

        executor.execute(.minimizePane(tabId: tab.id, paneId: paneOne.id))
        guard let minimized = store.tab(tab.id) else {
            Issue.record("Expected tab \(tab.id) after minimizing pane")
            return
        }
        #expect(minimized.activeMinimizedPaneIds == Set([paneOne.id]))
        #expect(minimized.activePaneId == paneTwo.id)

        executor.execute(.expandPane(tabId: tab.id, paneId: paneOne.id))
        guard let expanded = store.tab(tab.id) else {
            Issue.record("Expected tab \(tab.id) after expanding pane")
            return
        }
        #expect(expanded.activeMinimizedPaneIds == Set<UUID>())
        #expect(expanded.activePaneId == paneOne.id)
    }

    @Test("expandPane does not restore unrelated missing visible views")
    func expandPane_doesNotInvokeVisibleViewRestoreSweep() {
        let harness = makeHarness()
        let store = harness.store
        let viewRegistry = harness.viewRegistry
        let coordinator = harness.coordinator
        let executor = harness.executor
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        coordinator.windowLifecycleStore.recordTerminalContainerBounds(CGRect(x: 0, y: 0, width: 1000, height: 600))
        coordinator.windowLifecycleStore.recordLaunchLayoutSettled()

        let paneOne = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/one")!)),
            metadata: PaneMetadata(title: "One")
        )
        let paneTwo = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/two")!)),
            metadata: PaneMetadata(title: "Two")
        )
        let tab = Tab(paneId: paneOne.id)
        store.appendTab(tab)
        store.insertPane(
            paneTwo.id,
            inTab: tab.id,
            at: paneOne.id,
            direction: .horizontal,
            position: .after, sizingMode: .halveTarget
        )

        _ = coordinator.createViewForContent(
            pane: paneOne,
            initialFrame: CGRect(x: 0, y: 0, width: 500, height: 600)
        )
        #expect(viewRegistry.view(for: paneOne.id) != nil)
        #expect(viewRegistry.view(for: paneTwo.id) == nil)

        executor.execute(.minimizePane(tabId: tab.id, paneId: paneOne.id))
        executor.execute(.expandPane(tabId: tab.id, paneId: paneOne.id))

        #expect(viewRegistry.view(for: paneTwo.id) == nil)
    }

    private func assertFileViewPane(
        _ pane: Pane,
        repo: Repo,
        worktree: Worktree,
        viewRegistry: ViewRegistry
    ) {
        #expect(pane.repoId == repo.id)
        #expect(pane.worktreeId == worktree.id)
        #expect(pane.metadata.cwd == worktree.path)
        #expect(pane.metadata.title == "Files")
        let bridgeView = viewRegistry.view(for: pane.id)?.mountedContentViewForTesting as? BridgePaneMountView
        #expect(bridgeView?.controller.runtime.metadata.worktreeId == worktree.id)
        #expect(bridgeView?.controller.runtime.metadata.repoId == repo.id)
        #expect(bridgeView?.controller.runtime.metadata.cwd == worktree.path)
        guard case .bridgePanel(let state) = pane.content,
            state.panelKind == .fileViewer,
            case .workspace(let rootPath, let baseline) = state.source
        else {
            Issue.record("Expected Bridge file-viewer workspace source")
            return
        }
        #expect(rootPath == worktree.path.path)
        #expect(baseline == .localDefaultBranch(branchName: "main"))
        guard let script = bridgeView?.controller.bootstrapScriptSourceForTesting else {
            Issue.record("Expected mounted Bridge file-viewer bootstrap script")
            return
        }
        #expect(script.contains("const APP_PROTOCOL = \"worktree-file\""))
        #expect(script.contains("data-bridge-app-protocol"))
        #expect(!script.contains("data-bridge-worktree-file-source-spec"))
        #expect(!script.contains(repo.id.uuidString))
        #expect(!script.contains(worktree.id.uuidString))
        #expect(!script.contains(StableKey.fromPath(worktree.path)))
    }
}
