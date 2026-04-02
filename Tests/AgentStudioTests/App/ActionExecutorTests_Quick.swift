import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct ActionExecutorTestsQuick {
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
            windowLifecycleStore: WindowLifecycleStore()
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
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
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
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Web"))
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

        let paneOne = store.createPane(source: .floating(launchDirectory: nil, title: nil))
        let paneTwo = store.createPane(source: .floating(launchDirectory: nil, title: nil))
        let tab = Tab(paneId: paneOne.id)
        store.appendTab(tab)
        store.insertPane(
            paneTwo.id,
            inTab: tab.id,
            at: paneOne.id,
            direction: .horizontal,
            position: .after
        )

        executor.execute(.minimizePane(tabId: tab.id, paneId: paneOne.id))
        guard let minimized = store.tab(tab.id) else {
            Issue.record("Expected tab \(tab.id) after minimizing pane")
            return
        }
        #expect(minimized.minimizedPaneIds == Set([paneOne.id]))
        #expect(minimized.activePaneId == paneTwo.id)

        executor.execute(.expandPane(tabId: tab.id, paneId: paneOne.id))
        guard let expanded = store.tab(tab.id) else {
            Issue.record("Expected tab \(tab.id) after expanding pane")
            return
        }
        #expect(expanded.minimizedPaneIds == Set<UUID>())
        #expect(expanded.activePaneId == paneOne.id)
    }
}
