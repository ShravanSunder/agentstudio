import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("Terminal creation durability", .serialized)
struct WorkspaceTerminalCreationDurabilityTests {
    init() { installTestCoreAtomsIfNeeded() }

    @Test("new terminal ownership commits before surface launch", arguments: [false, true], [false, true])
    func createRequiresDurability(rejectWrite: Bool, worktreeTab: Bool) async throws {
        let workspaceID = UUIDv7.generate()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let datastore = try preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        let store = WorkspaceStore(
            identityAtom: WorkspaceIdentityAtom(workspaceId: workspaceID),
            sqliteDatastore: datastore, startsObserving: false)
        let action: WorkspaceActionCommand
        if worktreeTab {
            let repo = store.mutationCoordinator.addRepo(at: URL(filePath: "/tmp/agentstudio-terminal-creation-proof"))
            let worktree = try #require(repo.worktrees.first)
            action = .openNewTerminalInTab(worktreeId: worktree.id, launchDirectory: nil, title: nil)
        } else {
            action = .openFloatingTerminal(launchDirectory: nil, title: nil)
        }
        #expect(await store.flushAsync() == .persisted)
        let manager = HardeningSurfaceManager(createSurfaceResult: .failure(.ghosttyNotInitialized))
        var durablePaneSeenAtLaunch = false
        manager.onCreateSurface = { metadata in
            durablePaneSeenAtLaunch =
                (try? fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceID))?
                .panes.contains(where: { $0.id == metadata.paneId }) == true
        }
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store, viewRegistry: ViewRegistry(), runtime: SessionRuntime(store: store),
            surfaceManager: manager, runtimeRegistry: RuntimeRegistry(),
            windowLifecycleStore: WindowLifecycleAtom(), bridgePaneAttendance: BridgePaneAttendanceAtom())
        coordinator.windowLifecycleStore.recordTerminalContainerBounds(
            CGRect(x: 0, y: 0, width: 1000, height: 600))
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
            #expect(store.paneAtom.paneSnapshot().isEmpty)
            #expect(manager.createSurfaceCallCount == 0)
        } else {
            try await coordinator.execute(action)
            #expect(manager.createSurfaceCallCount == 1)
            #expect(durablePaneSeenAtLaunch)
            #expect(try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceID).panes.count == 1)
            #expect(store.paneAtom.paneSnapshot().count == 1)
        }
        await coordinator.shutdown()
    }
}
