import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteStoreBridgePersistenceTests", .serialized)
struct WorkspaceSQLiteStoreBridgePersistenceTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("SQLite flush after coordinator close removes parent drawer membership with two children")
    func sqliteFlushAfterCoordinatorClosePaneWithTwoDrawerChildrenPrunesDrawerMembership() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let identityAtom = WorkspaceIdentityAtom(workspaceId: UUIDv7.generate())
        identityAtom.replaceIdentity(
            workspaceId: workspaceId,
            workspaceName: "Drawer Close SQLite Workspace",
            createdAt: Date(timeIntervalSince1970: 1_700_000_086)
        )
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            identityAtom: identityAtom,
            sqliteDatastore: workspaceSQLiteDatastore(from: fixture.backend)
        )
        let anchorPane = store.createPane(title: "Anchor")
        let parentPane = store.createPane(title: "Parent")
        let tab = Tab(paneId: anchorPane.id, name: "Drawer Close")
        store.appendTab(tab)
        #expect(
            store.insertPane(
                parentPane.id,
                inTab: tab.id,
                at: anchorPane.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
        )
        let firstDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let secondDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let drawerId = try #require(store.pane(parentPane.id)?.drawer?.drawerId)

        #expect(store.mutationCoordinator.removePane(parentPane.id))
        let outcome = await store.flushAsync()

        guard outcome.succeeded else {
            Issue.record("Expected close-pane SQLite flush to succeed")
            return
        }
        let paneGraph = try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceId)
        #expect(paneGraph.panes.map(\.id) == [anchorPane.id])
        #expect(!paneGraph.panes.map(\.id).contains(parentPane.id))
        #expect(!paneGraph.panes.map(\.id).contains(firstDrawerPane.id))
        #expect(!paneGraph.panes.map(\.id).contains(secondDrawerPane.id))
        let tabGraph = try fixture.coreRepository.fetchTabGraph(workspaceId: workspaceId)
        let savedTab = try #require(tabGraph.tabs.single)
        #expect(savedTab.allPaneIds == [anchorPane.id])
        #expect(savedTab.arrangements.allSatisfy { $0.drawerViews[drawerId] == nil })
    }

    @Test("SQLite flush after detaching a drawer pane persists it as a layout pane")
    func sqliteFlushAfterDetachDrawerPanePersistsDetachedPaneAsLayout() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let identityAtom = WorkspaceIdentityAtom(workspaceId: UUIDv7.generate())
        identityAtom.replaceIdentity(
            workspaceId: workspaceId,
            workspaceName: "Drawer Detach SQLite Workspace",
            createdAt: Date(timeIntervalSince1970: 1_700_000_087)
        )
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            identityAtom: identityAtom,
            sqliteDatastore: workspaceSQLiteDatastore(from: fixture.backend)
        )
        let parentPane = store.createPane(title: "Parent")
        let tab = Tab(paneId: parentPane.id, name: "Drawer Detach")
        store.appendTab(tab)
        let detachedPane = try #require(store.addDrawerPane(to: parentPane.id))
        let remainingDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let drawerId = try #require(store.pane(parentPane.id)?.drawer?.drawerId)
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            windowLifecycleStore: WindowLifecycleAtom()
        )

        coordinator.execute(.detachDrawerPane(parentPaneId: parentPane.id, drawerPaneId: detachedPane.id))
        let outcome = await store.flushAsync()

        guard outcome.succeeded else {
            Issue.record("Expected detach-drawer-pane SQLite flush to succeed")
            return
        }
        let paneGraph = try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceId)
        let detachedRecord = try #require(paneGraph.panes.first { $0.id == detachedPane.id })
        #expect(detachedRecord.placement == .layout)
        let parentRecord = try #require(paneGraph.panes.first { $0.id == parentPane.id })
        #expect(parentRecord.drawer?.childPaneIds == [remainingDrawerPane.id])
        let tabGraph = try fixture.coreRepository.fetchTabGraph(workspaceId: workspaceId)
        let savedTab = try #require(tabGraph.tabs.single)
        #expect(Set(savedTab.allPaneIds) == Set([parentPane.id, remainingDrawerPane.id, detachedPane.id]))
        #expect(savedTab.arrangements.contains { $0.layout.contains(detachedPane.id) })
        #expect(
            savedTab.arrangements.compactMap { $0.drawerViews[drawerId]?.layout.paneIds }
                .allSatisfy { !$0.contains(detachedPane.id) }
        )
    }

    @Test("SQLite flush after background/reactivate preserves drawer child membership")
    func sqliteFlushAfterBackgroundReactivatePreservesDrawerChildMembership() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let identityAtom = WorkspaceIdentityAtom(workspaceId: UUIDv7.generate())
        identityAtom.replaceIdentity(
            workspaceId: workspaceId,
            workspaceName: "Drawer Background SQLite Workspace",
            createdAt: Date(timeIntervalSince1970: 1_700_000_088)
        )
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            identityAtom: identityAtom,
            sqliteDatastore: workspaceSQLiteDatastore(from: fixture.backend)
        )
        let anchorPane = store.createPane(title: "Anchor")
        let parentPane = store.createPane(title: "Parent")
        let tab = Tab(paneId: anchorPane.id, name: "Drawer Background")
        store.appendTab(tab)
        #expect(
            store.insertPane(
                parentPane.id,
                inTab: tab.id,
                at: anchorPane.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
        )
        let firstDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let secondDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let drawerId = try #require(store.pane(parentPane.id)?.drawer?.drawerId)

        #expect(store.mutationCoordinator.backgroundPane(parentPane.id))
        #expect(
            store.mutationCoordinator.reactivatePane(
                parentPane.id,
                inTab: tab.id,
                at: anchorPane.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
        )
        let outcome = await store.flushAsync()

        guard outcome.succeeded else {
            Issue.record("Expected background/reactivate SQLite flush to succeed")
            return
        }
        let tabGraph = try fixture.coreRepository.fetchTabGraph(workspaceId: workspaceId)
        let savedTab = try #require(tabGraph.tabs.single)
        #expect(
            Set(savedTab.allPaneIds) == Set([anchorPane.id, parentPane.id, firstDrawerPane.id, secondDrawerPane.id]))
        #expect(
            savedTab.arrangements.compactMap { $0.drawerViews[drawerId]?.layout.paneIds }
                .contains { Set($0) == Set([firstDrawerPane.id, secondDrawerPane.id]) }
        )

        let restoredStore = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            sqliteDatastore: workspaceSQLiteDatastore(from: fixture.backend)
        )
        await restoredStore.loadCanonicalComposition()
        let restoredTab = try #require(restoredStore.tab(tab.id))
        #expect(
            Set(restoredTab.allPaneIds) == Set([anchorPane.id, parentPane.id, firstDrawerPane.id, secondDrawerPane.id]))
        #expect(restoredStore.drawerView(forParent: parentPane.id)?.layout.paneIds.count == 2)
    }
}
