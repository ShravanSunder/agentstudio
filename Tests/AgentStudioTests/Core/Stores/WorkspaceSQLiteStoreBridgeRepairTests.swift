import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteStoreBridgeRepairTests", .serialized)
struct WorkspaceSQLiteStoreBridgeRepairTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("SQLite flush promotes a live custom arrangement when the default normalizes empty")
    func sqliteFlushPromotesLiveCustomArrangementWhenDefaultNormalizesEmpty() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let identityAtom = WorkspaceIdentityAtom()
        identityAtom.hydrate(
            workspaceId: workspaceId,
            workspaceName: "Default Empty Repair Workspace",
            createdAt: Date(timeIntervalSince1970: 1_700_000_085)
        )
        var recoveryEvents: [PersistenceRecoveryEvent] = []
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            identityAtom: identityAtom,
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            ),
            sqliteDatastore: workspaceSQLiteDatastore(from: fixture.backend),
            recoveryReporter: { event in recoveryEvents.append(event) }
        )
        let repo = store.addRepo(at: URL(filePath: "/tmp/agent-studio-sqlite-repair-repo"))
        let discoveredWorktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/agent-studio-sqlite-repair-repo"),
            isMainWorktree: true
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [discoveredWorktree])
        let worktree = try #require(store.repositoryTopologyAtom.repo(repo.id)?.worktrees.single)
        let customOnlyPane = store.createPane(
            launchDirectory: worktree.path,
            title: "Custom Only",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path),
        )
        let fallbackPane = store.createPane(
            title: "Fallback"
        )
        let invalidPaneId = UUID()
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: invalidPaneId),
            activePaneId: invalidPaneId
        )
        let customArrangement = PaneArrangement(
            name: "Custom",
            isDefault: false,
            layout: Layout(paneId: customOnlyPane.id),
            activePaneId: customOnlyPane.id
        )
        let brokenTab = Tab(
            name: "Broken",
            allPaneIds: [invalidPaneId, customOnlyPane.id],
            arrangements: [defaultArrangement, customArrangement],
            activeArrangementId: customArrangement.id
        )
        let fallbackTab = Tab(paneId: fallbackPane.id, name: "Fallback")
        store.appendTab(brokenTab)
        store.appendTab(fallbackTab)
        store.setActiveTab(brokenTab.id)

        let outcome = await store.flushAsync()

        guard outcome.succeeded else {
            Issue.record("Expected normalized SQLite flush to succeed")
            return
        }
        #expect(store.tab(brokenTab.id)?.allPaneIds == [customOnlyPane.id])
        #expect(store.tab(brokenTab.id)?.defaultArrangement.id == customArrangement.id)
        let shells = try fixture.coreRepository.fetchTabShells(workspaceId: workspaceId)
        #expect(shells.map(\.id) == [brokenTab.id, fallbackTab.id])
        let topology = try fixture.coreRepository.fetchRepositoryTopology(workspaceId: workspaceId)
        #expect(topology.repos.single?.id == repo.id)
        #expect(topology.repos.single?.worktrees.single?.id == worktree.id)
        let tabGraph = try fixture.coreRepository.fetchTabGraph(workspaceId: workspaceId)
        let repairedTab = try #require(tabGraph.tabs.first { $0.tabId == brokenTab.id })
        #expect(repairedTab.allPaneIds == [customOnlyPane.id])
        #expect(repairedTab.arrangements.first(where: \.isDefault)?.id == customArrangement.id)
        #expect(repairedTab.arrangements.first(where: \.isDefault)?.layout.paneIds == [customOnlyPane.id])
        let cursorState = try fixture.localRepository.fetchCursorState()
        #expect(cursorState.activeTabId == brokenTab.id)
        #expect(
            recoveryEvents.contains {
                $0.store == .workspace && $0.workspaceId == workspaceId && $0.recovery == .tabMembershipRepaired
            }
        )

        let restoredStore = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            ),
            sqliteDatastore: workspaceSQLiteDatastore(from: fixture.backend)
        )
        await restoredStore.restoreAsync()

        #expect(restoredStore.tab(brokenTab.id)?.allPaneIds == [customOnlyPane.id])
        #expect(restoredStore.pane(customOnlyPane.id)?.worktreeId == worktree.id)

        let recoveryEventCountAfterFirstFlush = recoveryEvents.count
        let secondOutcome = await store.flushAsync()
        #expect(secondOutcome.succeeded)
        #expect(recoveryEvents.count == recoveryEventCountAfterFirstFlush)
    }

    @Test("SQLite flush drops a drawer-only tab after the drawer parent is absent from layout")
    func sqliteFlushDropsDrawerOnlyTabAfterParentPrunesEmpty() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let identityAtom = WorkspaceIdentityAtom()
        identityAtom.hydrate(
            workspaceId: workspaceId,
            workspaceName: "Drawer Only Repair Workspace",
            createdAt: Date(timeIntervalSince1970: 1_700_000_086)
        )
        var recoveryEvents: [PersistenceRecoveryEvent] = []
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            identityAtom: identityAtom,
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            ),
            sqliteDatastore: workspaceSQLiteDatastore(from: fixture.backend),
            recoveryReporter: { event in recoveryEvents.append(event) }
        )
        let parentPane = store.createPane(title: "Parent")
        let drawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let drawerId = try #require(store.pane(parentPane.id)?.drawer?.drawerId)
        let fallbackPane = store.createPane(
            title: "Fallback"
        )
        let drawerOnlyArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(),
            activePaneId: nil,
            drawerViews: [
                drawerId: DrawerView(
                    layout: DrawerGridLayout(topRow: Layout(paneId: drawerPane.id)),
                    activeChildId: drawerPane.id
                )
            ]
        )
        let brokenTab = Tab(
            name: "Drawer Only",
            allPaneIds: [drawerPane.id],
            arrangements: [drawerOnlyArrangement],
            activeArrangementId: drawerOnlyArrangement.id
        )
        let fallbackTab = Tab(paneId: fallbackPane.id, name: "Fallback")
        store.appendTab(brokenTab)
        store.appendTab(fallbackTab)
        store.setActiveTab(brokenTab.id)

        let outcome = await store.flushAsync()

        guard outcome.succeeded else {
            Issue.record("Expected drawer-only tab repair SQLite flush to succeed")
            return
        }
        let shells = try fixture.coreRepository.fetchTabShells(workspaceId: workspaceId)
        #expect(shells.map(\.id) == [fallbackTab.id])
        let tabGraph = try fixture.coreRepository.fetchTabGraph(workspaceId: workspaceId)
        #expect(tabGraph.tabs.map(\.tabId) == [fallbackTab.id])
        let cursorState = try fixture.localRepository.fetchCursorState()
        #expect(cursorState.activeTabId == fallbackTab.id)
        #expect(store.tab(brokenTab.id) == nil)
        #expect(store.activeTabId == fallbackTab.id)
        #expect(
            recoveryEvents.contains {
                $0.store == .workspace && $0.workspaceId == workspaceId && $0.recovery == .tabMembershipRepaired
            }
        )
    }

    @Test("SQLite flush after coordinator close removes parent drawer membership with two children")
    func sqliteFlushAfterCoordinatorClosePaneWithTwoDrawerChildrenPrunesDrawerMembership() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let identityAtom = WorkspaceIdentityAtom()
        identityAtom.hydrate(
            workspaceId: workspaceId,
            workspaceName: "Drawer Close SQLite Workspace",
            createdAt: Date(timeIntervalSince1970: 1_700_000_086)
        )
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            identityAtom: identityAtom,
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            ),
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
        let identityAtom = WorkspaceIdentityAtom()
        identityAtom.hydrate(
            workspaceId: workspaceId,
            workspaceName: "Drawer Detach SQLite Workspace",
            createdAt: Date(timeIntervalSince1970: 1_700_000_087)
        )
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            identityAtom: identityAtom,
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            ),
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
        let identityAtom = WorkspaceIdentityAtom()
        identityAtom.hydrate(
            workspaceId: workspaceId,
            workspaceName: "Drawer Background SQLite Workspace",
            createdAt: Date(timeIntervalSince1970: 1_700_000_088)
        )
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            identityAtom: identityAtom,
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            ),
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
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            ),
            sqliteDatastore: workspaceSQLiteDatastore(from: fixture.backend)
        )
        await restoredStore.restoreAsync()
        let restoredTab = try #require(restoredStore.tab(tab.id))
        #expect(
            Set(restoredTab.allPaneIds) == Set([anchorPane.id, parentPane.id, firstDrawerPane.id, secondDrawerPane.id]))
        #expect(restoredStore.drawerView(forParent: parentPane.id)?.layout.paneIds.count == 2)
    }
}
