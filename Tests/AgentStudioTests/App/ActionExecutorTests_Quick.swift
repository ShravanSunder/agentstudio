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
            runtime: runtime
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

    @Test("openWebview creates a tab and registers a webview pane")
    func openWebview_addsTabAndRegistersView() {
        let harness = makeHarness()
        let store = harness.store
        let viewRegistry = harness.viewRegistry
        let executor = harness.executor
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pane = executor.openWebview(url: URL(string: "https://example.com")!)

        #expect(pane != nil)
        #expect(store.tabs.count == 1)
        #expect(store.activeTabId == store.tabs[0].id)
        #expect(viewRegistry.view(for: pane!.id) is WebviewPaneView)
        #expect(viewRegistry.webviewView(for: pane!.id) != nil)
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
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Web"))
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        _ = coordinator.createViewForContent(pane: pane)
        guard let beforeView = viewRegistry.view(for: pane.id) else {
            Issue.record("Expected webview view to exist before repair")
            return
        }

        viewRegistry.unregister(pane.id)

        let revisionBefore = store.viewRevision
        executor.execute(.repair(.recreateSurface(paneId: pane.id)))

        let afterView = viewRegistry.view(for: pane.id)
        #expect(afterView != nil)
        #expect(afterView !== beforeView)
        #expect(store.viewRevision == revisionBefore + 1)
    }

    @Test("minimizePane hides pane and expandPane restores active pane")
    func minimize_then_expandPane_updatesTransientState() {
        let harness = makeHarness()
        let store = harness.store
        let executor = harness.executor
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let paneOne = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let paneTwo = store.createPane(source: .floating(workingDirectory: nil, title: nil))
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
