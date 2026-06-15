import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneCoordinatorDrawerUndoTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private struct Harness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let runtime: SessionRuntime
        let coordinator: PaneCoordinator
        let surfaceManager: MockPaneCoordinatorSurfaceManagerForHarness
        let tempDir: URL
    }

    private func makeHarness() -> Harness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-drawer-undo-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let surfaceManager = MockPaneCoordinatorSurfaceManagerForHarness()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: surfaceManager,
            runtimeRegistry: RuntimeRegistry(),
            windowLifecycleStore: WindowLifecycleAtom()
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

    private func makeWebviewPane(_ store: WorkspaceStore, title: String) -> Pane {
        let url = URL(string: "https://example.com/\(UUID().uuidString)")!
        return store.createPane(
            content: .webview(WebviewState(url: url, showNavigation: true)),
            metadata: PaneMetadata(title: title)
        )
    }

    private func makeWebviewDrawerPane(_ store: WorkspaceStore, parentPaneId: UUID, title: String) -> Pane? {
        let url = URL(string: "https://example.com/\(UUID().uuidString)")!
        guard
            let drawerPane = store.paneAtom.addDrawerPane(
                to: parentPaneId,
                content: .webview(WebviewState(url: url, showNavigation: true)),
                metadata: PaneMetadata(title: title)
            )
        else {
            return nil
        }
        if let tabId = store.tabLayoutAtom.tabContaining(paneId: parentPaneId)?.id,
            let drawerId = store.paneAtom.pane(parentPaneId)?.drawer?.drawerId
        {
            store.tabArrangementAtom.addDrawerPaneView(
                drawerId: drawerId,
                parentPaneId: parentPaneId,
                drawerPaneId: drawerPane.id,
                inTab: tabId
            )
        }
        return drawerPane
    }

    @Test("undoPaneClose restores a parent pane with drawer child tab membership")
    func undoPaneCloseParentPaneRestoresDrawerChildMembership() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let anchorPane = makeWebviewPane(harness.store, title: "Anchor")
        let parentPane = makeWebviewPane(harness.store, title: "Parent")
        let tab = Tab(paneId: anchorPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.insertPane(
            parentPane.id,
            inTab: tab.id,
            at: anchorPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        let firstDrawerPane = try #require(
            makeWebviewDrawerPane(harness.store, parentPaneId: parentPane.id, title: "First Drawer")
        )
        let secondDrawerPane = try #require(
            makeWebviewDrawerPane(harness.store, parentPaneId: parentPane.id, title: "Second Drawer")
        )
        let drawerId = try #require(harness.store.pane(parentPane.id)?.drawer?.drawerId)

        harness.coordinator.execute(.closePane(tabId: tab.id, paneId: parentPane.id))
        harness.coordinator.undoCloseTab()

        let restoredTab = try #require(harness.store.tab(tab.id))
        #expect(restoredTab.allPaneIds.contains(parentPane.id))
        #expect(restoredTab.allPaneIds.contains(firstDrawerPane.id))
        #expect(restoredTab.allPaneIds.contains(secondDrawerPane.id))
        let restoredDrawerViews = restoredTab.arrangements.compactMap { $0.drawerViews[drawerId] }
        #expect(restoredDrawerViews.count == restoredTab.arrangements.count)
        #expect(restoredDrawerViews.allSatisfy { $0.layout.paneIds == [firstDrawerPane.id, secondDrawerPane.id] })
    }
}
