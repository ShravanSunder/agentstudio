import Foundation
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
}
