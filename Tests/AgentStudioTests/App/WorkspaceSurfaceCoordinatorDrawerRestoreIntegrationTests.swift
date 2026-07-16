import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceDrawerRestoreIntegrationTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private let fixtureSessionConfiguration = SessionConfiguration(
        isEnabled: true,
        zmxPath: "/tmp/fake-zmx",
        zmxDir: "/tmp/fake-zmx-dir",
        healthCheckInterval: 30,
        maxCheckpointAge: 60
    )

    private let trustedBounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    private struct Harness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let runtime: SessionRuntime
        let coordinator: WorkspaceSurfaceCoordinator
        let windowLifecycleStore: WindowLifecycleAtom
        let surfaceManager: DrawerRestoreCapturingSurfaceManager
        let tempDir: URL
    }

    private func makeHarness() -> Harness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-drawer-restore-tests-\(UUID().uuidString)")
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let windowLifecycleStore = WindowLifecycleAtom()
        let surfaceManager = DrawerRestoreCapturingSurfaceManager()
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: surfaceManager,
            runtimeRegistry: .shared,
            windowLifecycleStore: windowLifecycleStore
        )
        coordinator.sessionConfig = fixtureSessionConfiguration
        coordinator.terminalRestoreRuntime = TerminalRestoreRuntime(
            sessionConfiguration: fixtureSessionConfiguration
        )
        return Harness(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            coordinator: coordinator,
            windowLifecycleStore: windowLifecycleStore,
            surfaceManager: surfaceManager,
            tempDir: tempDir
        )
    }

    @Test
    func toggleDrawer_restoresPreviouslySkippedDrawerPane_whenVisibilityTupleBecomesTrue() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let parentPane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: parentPane.id, name: "Collapsed Drawer")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        harness.store.toggleDrawer(for: parentPane.id)
        #expect(harness.store.pane(parentPane.id)?.drawer?.isExpanded == false)

        harness.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        await harness.coordinator.restoreAllViews(in: trustedBounds)
        #expect(harness.surfaceManager.createdPaneIds == [parentPane.id])

        harness.coordinator.execute(.toggleDrawer(paneId: parentPane.id))

        #expect(harness.store.pane(parentPane.id)?.drawer?.isExpanded == true)
        #expect(harness.surfaceManager.createdPaneIds == [parentPane.id, drawerPane.id])
        let config = try #require(harness.surfaceManager.createdConfigsByPaneId[drawerPane.id])
        #expect(config.initialFrame != nil)
    }

    @Test
    func expandDrawerPane_restoresPreviouslyMinimizedDrawerPane_whenVisibilityTupleBecomesTrue() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let parentPane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: parentPane.id, name: "Minimized Drawer")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let visibleDrawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        let minimizedDrawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        harness.coordinator.execute(
            .minimizeDrawerPane(parentPaneId: parentPane.id, drawerPaneId: minimizedDrawerPane.id)
        )

        harness.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        await harness.coordinator.restoreAllViews(in: trustedBounds)
        #expect(harness.surfaceManager.createdPaneIds == [parentPane.id, visibleDrawerPane.id])

        harness.coordinator.execute(
            .expandDrawerPane(parentPaneId: parentPane.id, drawerPaneId: minimizedDrawerPane.id)
        )

        #expect(harness.store.drawerView(forParent: parentPane.id)?.activeChildId == minimizedDrawerPane.id)
        #expect(harness.surfaceManager.createdPaneIds == [parentPane.id, visibleDrawerPane.id, minimizedDrawerPane.id])
        let config = try #require(harness.surfaceManager.createdConfigsByPaneId[minimizedDrawerPane.id])
        #expect(config.initialFrame != nil)
    }

    @Test
    func setActiveDrawerPane_restoresPreviouslySkippedDrawerPane_whenSelectionMakesItVisible() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let parentPane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: parentPane.id, name: "Selectable Drawer")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let firstDrawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        let secondDrawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        harness.store.setActiveDrawerPane(firstDrawerPane.id, in: parentPane.id)

        harness.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)

        harness.coordinator.execute(
            .setActiveDrawerPane(parentPaneId: parentPane.id, drawerPaneId: secondDrawerPane.id)
        )

        #expect(harness.store.drawerView(forParent: parentPane.id)?.activeChildId == secondDrawerPane.id)
        #expect(harness.surfaceManager.createdPaneIds == [secondDrawerPane.id])
        let config = try #require(harness.surfaceManager.createdConfigsByPaneId[secondDrawerPane.id])
        #expect(config.initialFrame != nil)
    }

    @Test
    func closeUndoFreshRestoreThenSelectDrawerPane_restoresColdRestoredSkippedDrawerPane() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-terminal-restore-composed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let identityAtom = WorkspaceIdentityAtom(
            workspaceId: workspaceId,
            workspaceName: "Composed Drawer Restore",
            createdAt: Date(timeIntervalSince1970: 1_700_000_089)
        )
        var recoveryEvents: [PersistenceRecoveryEvent] = []
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            identityAtom: identityAtom,
            persistor: WorkspacePersistor(workspacesDir: tempDir),
            sqliteDatastore: workspaceSQLiteDatastore(from: fixture.backend),
            recoveryReporter: { event in recoveryEvents.append(event) }
        )
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let windowLifecycleStore = WindowLifecycleAtom()
        let surfaceManager = DrawerRestoreCapturingSurfaceManager()
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: surfaceManager,
            runtimeRegistry: RuntimeRegistry(),
            windowLifecycleStore: windowLifecycleStore
        )
        coordinator.sessionConfig = fixtureSessionConfiguration
        coordinator.terminalRestoreRuntime = TerminalRestoreRuntime(
            sessionConfiguration: fixtureSessionConfiguration
        )
        let repo = store.addRepo(at: tempDir)
        let worktree = try #require(repo.worktrees.first)
        let parentPane = store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: parentPane.id, name: "Composed Drawer")
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        let firstDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let secondDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        store.setActiveDrawerPane(firstDrawerPane.id, in: parentPane.id)
        coordinator.execute(
            .minimizeDrawerPane(parentPaneId: parentPane.id, drawerPaneId: secondDrawerPane.id)
        )

        coordinator.execute(.closeTab(tabId: tab.id))
        coordinator.undoCloseTab()
        let flushOutcome = await store.flushAsync()

        #expect(flushOutcome.succeeded)
        #expect(
            !recoveryEvents.contains {
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
        let restoredViewRegistry = ViewRegistry()
        let restoredRuntime = SessionRuntime(store: restoredStore)
        let restoredWindowLifecycleStore = WindowLifecycleAtom()
        let restoredSurfaceManager = DrawerRestoreCapturingSurfaceManager()
        let restoredCoordinator = WorkspaceSurfaceCoordinator(
            store: restoredStore,
            viewRegistry: restoredViewRegistry,
            runtime: restoredRuntime,
            surfaceManager: restoredSurfaceManager,
            runtimeRegistry: RuntimeRegistry(),
            windowLifecycleStore: restoredWindowLifecycleStore
        )
        restoredCoordinator.sessionConfig = fixtureSessionConfiguration
        restoredCoordinator.terminalRestoreRuntime = TerminalRestoreRuntime(
            sessionConfiguration: fixtureSessionConfiguration
        )

        restoredWindowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        await restoredCoordinator.restoreAllViews(in: trustedBounds)
        #expect(restoredSurfaceManager.createdPaneIds == [parentPane.id, firstDrawerPane.id])

        restoredCoordinator.execute(
            .expandDrawerPane(parentPaneId: parentPane.id, drawerPaneId: secondDrawerPane.id)
        )

        let restoredTab = try #require(restoredStore.tab(tab.id))
        let restoredDrawerView = try #require(restoredStore.drawerView(forParent: parentPane.id))
        #expect(restoredTab.allPaneIds == [parentPane.id, firstDrawerPane.id, secondDrawerPane.id])
        #expect(restoredDrawerView.activeChildId == secondDrawerPane.id)
        #expect(restoredSurfaceManager.createdPaneIds == [parentPane.id, firstDrawerPane.id, secondDrawerPane.id])
    }
}

@MainActor
private final class DrawerRestoreCapturingSurfaceManager: WorkspaceSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>

    private(set) var createdPaneIds: [UUID] = []
    private(set) var createdConfigsByPaneId: [UUID: Ghostty.SurfaceConfiguration] = [:]

    init() {
        self.cwdStream = AsyncStream { continuation in
            continuation.onTermination = { _ in }
        }
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { cwdStream }

    func syncFocus(activeSurfaceId _: UUID?) {}

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        if let paneId = metadata.paneId {
            createdPaneIds.append(paneId)
            createdConfigsByPaneId[paneId] = config
        }
        return .failure(.operationFailed("capture only"))
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
