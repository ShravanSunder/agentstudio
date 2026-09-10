import AgentStudioInfrastructure
import Foundation
import Observation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

enum TerminalDurabilityCreationPath: CaseIterable, Sendable {
    case floatingTab, worktreeTab, floatingSplit, worktreeSplit, drawerAppend, drawerInsert

    @MainActor func action(in store: WorkspaceStore) throws -> WorkspaceActionCommand {
        if self == .floatingTab { return .openFloatingTerminal(launchDirectory: nil, title: nil) }
        let repo = store.mutationCoordinator.addRepo(at: URL(filePath: "/tmp/agentstudio-terminal-creation-proof"))
        let worktree = try #require(repo.worktrees.first)
        if self == .worktreeTab {
            return .openNewTerminalInTab(worktreeId: worktree.id, launchDirectory: nil, title: nil)
        }
        let anchor = store.createPane()
        let tab = Tab(paneId: anchor.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        if self == .worktreeSplit { return .openWorktreeInPane(worktreeId: worktree.id) }
        if self == .drawerAppend { return .addDrawerPane(parentPaneId: anchor.id) }
        if self == .drawerInsert {
            let child = try #require(store.addDrawerPane(to: anchor.id))
            return .insertDrawerPane(
                parentPaneId: anchor.id, targetDrawerPaneId: child.id, direction: .right, sizingMode: .halveTarget)
        }
        return .insertPane(
            source: .newTerminal, targetTabId: tab.id, targetPaneId: anchor.id,
            direction: .right, sizingMode: .halveTarget)
    }
}

@MainActor
@Suite("Terminal creation durability", .serialized)
struct WorkspaceTerminalCreationDurabilityTests {
    @MainActor
    private final class PublicationObservation {
        var observedNewPane = false
        var missingSlotIDs: [UUID] = []
    }

    init() { installTestCoreAtomsIfNeeded() }

    @Test(
        "new terminal ownership commits before surface launch", arguments: [false, true],
        TerminalDurabilityCreationPath.allCases)
    func createRequiresDurability(rejectWrite: Bool, path: TerminalDurabilityCreationPath) async throws {
        let workspaceID = UUIDv7.generate()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let datastore = try preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        let store = WorkspaceStore(
            identityAtom: WorkspaceIdentityAtom(workspaceId: workspaceID),
            sqliteDatastore: datastore, startsObserving: false)
        let action = try path.action(in: store)
        let initialPaneIDs = Set(store.paneAtom.paneSnapshot().keys)
        #expect(await store.flushAsync() == .persisted)
        let manager = HardeningSurfaceManager(createSurfaceResult: .failure(.ghosttyNotInitialized))
        var durablePaneSeenAtLaunch = false
        manager.onCreateSurface = { metadata in
            durablePaneSeenAtLaunch =
                (try? fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceID))?
                .panes.contains(where: { $0.id == metadata.paneId }) == true
        }
        let registry = ViewRegistry()
        let publication = PublicationObservation()
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store, viewRegistry: registry, runtime: SessionRuntime(store: store),
            surfaceManager: manager, runtimeRegistry: RuntimeRegistry(),
            windowLifecycleStore: WindowLifecycleAtom(), bridgePaneAttendance: BridgePaneAttendanceAtom())
        coordinator.windowLifecycleStore.recordTerminalContainerBounds(
            CGRect(x: 0, y: 0, width: 1000, height: 600))
        // This is the synchronous observation boundary used by layout readers.
        // Read without slot(for:)'s fatal assertion so a missing prerequisite is
        // reported as a regression rather than aborting the entire test process.
        withObservationTracking {
            _ = store.tabArrangementAtom.arrangementStates
        } onChange: { [weak store, weak registry, weak publication] in
            MainActor.assumeIsolated {
                guard let store, let registry, let publication else { return }
                let newPaneIDs = Set(store.paneAtom.paneSnapshot().keys).subtracting(initialPaneIDs)
                publication.observedNewPane = !newPaneIDs.isEmpty
                publication.missingSlotIDs = newPaneIDs.filter { registry.peekSlotForTesting($0) == nil }
            }
        }
        if rejectWrite {
            try await fixture.coreRepository.databaseWriter.write { database in
                try database.execute(
                    sql: """
                        CREATE TRIGGER reject_terminal_creation BEFORE INSERT ON pane_content_terminal
                        BEGIN SELECT RAISE(ABORT, 'injected terminal registration failure'); END
                        """)
            }
            await #expect(throws: (any Error).self) {
                try await coordinator.execute(action)
            }
            #expect(Set(store.paneAtom.paneSnapshot().keys) == initialPaneIDs)
            #expect(manager.createSurfaceCallCount == 0)
            #expect(!publication.observedNewPane)
        } else {
            try await coordinator.execute(action)
            #expect(manager.createSurfaceCallCount == 1)
            #expect(durablePaneSeenAtLaunch)
            #expect(publication.observedNewPane)
            #expect(publication.missingSlotIDs.isEmpty)
            #expect(
                try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceID).panes.count == initialPaneIDs.count
                    + 1)
            #expect(store.paneAtom.paneSnapshot().count == initialPaneIDs.count + 1)
        }
        await coordinator.shutdown()
    }

    @Test("a delayed creation request cannot recreate a permanently discarded pane")
    func discardedPaneCannotBeCreatedFromOldCapture() async throws {
        let workspaceID = UUIDv7.generate()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let datastore = try preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        let store = WorkspaceStore(
            identityAtom: WorkspaceIdentityAtom(workspaceId: workspaceID),
            sqliteDatastore: datastore, startsObserving: false)
        let pane = store.createPane(residency: .backgrounded)
        try #require(await store.flushAsync() == .persisted)
        let manager = HardeningSurfaceManager(createSurfaceResult: .failure(.ghosttyNotInitialized))
        let registry = ViewRegistry()
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store, viewRegistry: registry, runtime: SessionRuntime(store: store),
            surfaceManager: manager, runtimeRegistry: RuntimeRegistry(),
            windowLifecycleStore: WindowLifecycleAtom(), bridgePaneAttendance: BridgePaneAttendanceAtom())
        coordinator.sessionConfig = SessionConfiguration(
            isEnabled: true, zmxPath: "/test/zmx", zmxDir: "/tmp/unused-creation-regression",
            healthCheckInterval: 30, maxCheckpointAge: 3600)
        let authority = try #require(coordinator.terminalSurfaceCreationAuthority(for: pane))
        do {
            try await coordinator.execute(.purgeOrphanedPane(paneId: pane.id))
            _ = coordinator.createTopologyIndependentTerminalView(
                for: pane, initialFrame: CGRect(x: 0, y: 0, width: 400, height: 300), authority: authority)
            coordinator.registerTerminalPlaceholderIfNeeded(for: pane, mode: .preparing)
            #expect(manager.createSurfaceCallCount == 0)
            #expect(registry.view(for: pane.id) == nil)
            #expect(store.paneAtom.pane(pane.id) == nil)
        } catch {
            await coordinator.shutdown()
            throw error
        }
        await coordinator.shutdown()
    }

    @Test(
        "ensuring a mounted terminal preserves its surface and does not create another",
        arguments: [false, true])
    func ensureMountedTerminalIsIdempotent(requestsPlaceholderFirst: Bool) async throws {
        let workspaceID = UUIDv7.generate()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let datastore = try preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        let store = WorkspaceStore(
            identityAtom: WorkspaceIdentityAtom(workspaceId: workspaceID),
            sqliteDatastore: datastore, startsObserving: false)
        let pane = try await store.createTerminalPane(
            metadata: PaneMetadata(title: "Existing terminal"), placement: .newTab,
            nameForPane: { _ in "Existing terminal" }, willPublish: { _ in })
        let manager = HardeningSurfaceManager(createSurfaceResult: .failure(.ghosttyNotInitialized))
        let registry = ViewRegistry()
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store, viewRegistry: registry, runtime: SessionRuntime(store: store),
            surfaceManager: manager, runtimeRegistry: RuntimeRegistry(),
            windowLifecycleStore: WindowLifecycleAtom(), bridgePaneAttendance: BridgePaneAttendanceAtom())
        coordinator.windowLifecycleStore.recordTerminalContainerBounds(
            CGRect(x: 0, y: 0, width: 1000, height: 600))
        let surfaceID = UUIDv7.generate()
        let mounted = TerminalPaneMountView(restoredSurfaceId: surfaceID, paneId: pane.id)
        coordinator.registerHostedView(mountedView: mounted, for: pane.id)

        if requestsPlaceholderFirst {
            coordinator.registerTerminalPlaceholderIfNeeded(for: pane, mode: .preparing)
        }
        coordinator.ensureTerminalPaneView(pane)
        coordinator.ensureTerminalPaneView(pane)

        let authority = try #require(coordinator.terminalSurfaceCreationAuthority(for: pane))
        let result = coordinator.createTopologyIndependentTerminalView(
            for: pane, initialFrame: CGRect(x: 0, y: 0, width: 400, height: 300), authority: authority)
        if case .mounted(let content) = result {
            #expect(content.surfaceID == surfaceID)
        } else {
            Issue.record("A repeated construction request must reuse the mounted terminal")
        }

        #expect(manager.createSurfaceCallCount == 0)
        #expect(registry.terminalView(for: pane.id) === mounted)
        #expect(mounted.surfaceId == surfaceID)
        #expect(mounted.currentPlaceholderView == nil)
        coordinator.unregisterHostedView(for: pane.id)
        await coordinator.shutdown()
    }

}
