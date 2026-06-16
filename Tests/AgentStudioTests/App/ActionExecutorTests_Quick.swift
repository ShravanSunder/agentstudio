import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct ActionExecutorTestsQuick {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private struct ActionExecutorHarness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let runtime: SessionRuntime
        let coordinator: PaneCoordinator
        let executor: ActionExecutor
        let tempDir: URL
    }

    private func makeHarness() -> ActionExecutorHarness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-action-executor-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore(persistor: persistor)
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            windowLifecycleStore: WindowLifecycleAtom()
        )
        let executor = ActionExecutor(coordinator: coordinator, store: store)
        return ActionExecutorHarness(
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

    @Test("openBridgeReview creates a generic read-only review tab")
    func openBridgeReview_addsGenericBridgeTabAndRegistersView() {
        let harness = makeHarness()
        let store = harness.store
        let viewRegistry = harness.viewRegistry
        let executor = harness.executor
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pane = executor.openBridgeReview()

        #expect(pane != nil)
        #expect(store.tabs.count == 1)
        #expect(store.activeTabId == store.tabs[0].id)
        #expect(viewRegistry.view(for: pane!.id) != nil)
        #expect(viewRegistry.view(for: pane!.id)?.mountedContentViewForTesting is BridgePaneMountView)
        guard case .bridgePanel(let state) = pane?.content else {
            Issue.record("Expected bridge panel content")
            return
        }
        #expect(state.panelKind == .diffViewer)
        #expect(state.source == nil)
        #expect(pane?.metadata.title == "Bridge Review")
        #expect(pane?.metadata.contentType == .diff)
        #expect(pane?.repoId == nil)
        #expect(pane?.worktreeId == nil)
        #expect(pane?.metadata.cwd == nil)
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
        #expect(baseline == .unstaged)
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
        #expect(baseline == .unstaged)
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
}
