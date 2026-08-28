import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

@MainActor
@Suite("WorkspaceSurfaceCoordinator pull request demand", .serialized, .timeLimit(.minutes(1)))
struct WorkspaceSurfaceCoordinatorPullRequestDemandTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("visible active tab and sidebar demand is content-distinct and clears with the window")
    func visibleDemandTracksTabSidebarAndWindow() async throws {
        try await withAsyncTestCoreAtoms { coreAtoms in
            let store = WorkspaceStore()
            let firstRepo = store.addRepo(at: URL(fileURLWithPath: "/tmp/pr-demand-first"))
            let firstWorktree = try #require(firstRepo.worktrees.first)
            let firstPane = store.createPane(
                launchDirectory: firstWorktree.path,
                facets: PaneContextFacets(
                    repoId: firstRepo.id,
                    worktreeId: firstWorktree.id,
                    cwd: firstWorktree.path
                )
            )
            let firstTab = Tab(paneId: firstPane.id)
            store.appendTab(firstTab)

            let secondRepo = store.addRepo(at: URL(fileURLWithPath: "/tmp/pr-demand-second"))
            let secondWorktree = try #require(secondRepo.worktrees.first)
            let secondPane = store.createPane(
                launchDirectory: secondWorktree.path,
                facets: PaneContextFacets(
                    repoId: secondRepo.id,
                    worktreeId: secondWorktree.id,
                    cwd: secondWorktree.path
                )
            )
            let secondTab = Tab(paneId: secondPane.id)
            store.appendTab(secondTab)
            store.setActiveTab(firstTab.id)

            let source = PullRequestDemandRecordingFilesystemSource()
            let windowLifecycle = WindowLifecycleAtom()
            let gitStatusPhysicalGate = AgentStudioGitStatusPhysicalGate()
            let coordinator = WorkspaceSurfaceCoordinator(
                store: store,
                viewRegistry: ViewRegistry(),
                runtime: SessionRuntime(store: store),
                surfaceManager: PullRequestDemandSurfaceManager(),
                runtimeRegistry: RuntimeRegistry(),
                paneEventBus: EventBus<RuntimeEnvelope>(),
                gitWorkingTreeStatusProvider: AgentStudioGitWorkingTreeStatusProvider(
                    physicalGate: gitStatusPhysicalGate
                ),
                gitStatusPhysicalGate: gitStatusPhysicalGate,
                filesystemSource: source,
                windowLifecycleStore: windowLifecycle,
                bridgePaneAttendance: BridgePaneAttendanceAtom()
            )
            let owningWindowId = UUIDv7.generate()
            coreAtoms.applicationEntityRecency.hydrate([])
            coreAtoms.sidebarVisibleWorktreesRuntime.setVisibleWorktreeIds([])
            coordinator.bindPullRequestDemand(toOwningWindowId: owningWindowId)
            #expect(await source.waitForLastSnapshot([]))

            windowLifecycle.recordWindowRegistered(owningWindowId)
            windowLifecycle.recordWindowPresentation(
                WindowPresentationFacts(isVisible: true, isMiniaturized: false, isOccluded: false),
                for: owningWindowId
            )
            #expect(await source.waitForLastSnapshot([firstWorktree.id, secondWorktree.id]))

            let snapshotCountBeforeViewportChange = await source.snapshotCount
            let viewportOnlyWorktreeId = UUIDv7.generate()
            coreAtoms.sidebarVisibleWorktreesRuntime.setVisibleWorktreeIds([viewportOnlyWorktreeId])
            await Task.yield()
            #expect(await source.snapshotCount == snapshotCountBeforeViewportChange)

            store.setActiveTab(secondTab.id)
            #expect(
                await source.waitForLastSnapshot([firstWorktree.id, secondWorktree.id])
            )

            await source.suspendNextSnapshot([])
            windowLifecycle.recordWindowPresentation(
                WindowPresentationFacts(isVisible: false, isMiniaturized: false, isOccluded: true),
                for: owningWindowId
            )
            #expect(await source.waitForLastSnapshot([]))
            let settlementTask = Task { @MainActor in
                await coordinator.settleRepositoryFactDemandAdmissionForPerformanceProof()
            }
            await Task.yield()
            #expect(await source.repositoryFactDemandAdmissionSettlementCount == 0)
            await source.releaseSuspendedSnapshot()
            await settlementTask.value
            #expect(await source.repositoryFactDemandAdmissionSettlementCount == 1)

            coreAtoms.sidebarVisibleWorktreesRuntime.setVisibleWorktreeIds([])
            await coordinator.shutdown()
        }
    }

}

private actor PullRequestDemandRecordingFilesystemSource: WorkspaceFilesystemSourceManaging {
    private var demandSnapshots: [Set<UUID>] = []
    private var snapshotWaiters: [UUID: AsyncStream<Set<UUID>>.Continuation] = [:]
    private var suspendedSnapshot: Set<UUID>?
    private var suspendedSnapshotContinuation: CheckedContinuation<Void, Never>?
    private(set) var repositoryFactDemandAdmissionSettlementCount = 0

    var snapshotCount: Int { demandSnapshots.count }
    var lastSnapshot: Set<UUID>? { demandSnapshots.last }

    func start() async {}
    func shutdown() async {}
    func register(worktreeId: UUID, repoId: UUID, rootPath: URL) async {}
    func unregister(worktreeId: UUID) async {}
    func assertTopology(_ assertion: FilesystemTopologyAssertion) async {}
    func setActivity(worktreeId: UUID, isActiveInApp: Bool) async {}
    func setActivePaneWorktree(worktreeId: UUID?) async {}
    func setSidebarVisibleWorktrees(_ worktreeIds: Set<UUID>) async {}

    func setPullRequestDemandWorktrees(_ worktreeIds: Set<UUID>) async {
        demandSnapshots.append(worktreeIds)
        for waiter in snapshotWaiters.values {
            waiter.yield(worktreeIds)
        }
        if suspendedSnapshot == worktreeIds {
            suspendedSnapshot = nil
            await withCheckedContinuation { continuation in
                suspendedSnapshotContinuation = continuation
            }
        }
    }

    func setRepositoryFactDemand(_ snapshot: RepositoryFactDemandSnapshot) async {
        await setPullRequestDemandWorktrees(snapshot.forgeDemandedWorktreeIds)
    }

    func waitForRepositoryFactDemandAdmission() async {
        repositoryFactDemandAdmissionSettlementCount += 1
    }

    func suspendNextSnapshot(_ worktreeIds: Set<UUID>) {
        suspendedSnapshot = worktreeIds
    }

    func releaseSuspendedSnapshot() {
        suspendedSnapshotContinuation?.resume()
        suspendedSnapshotContinuation = nil
    }

    func waitForLastSnapshot(_ expected: Set<UUID>) async -> Bool {
        if demandSnapshots.last == expected { return true }
        let waiterId = UUIDv7.generate()
        let (stream, continuation) = AsyncStream.makeStream(
            of: Set<UUID>.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        snapshotWaiters[waiterId] = continuation
        defer {
            snapshotWaiters.removeValue(forKey: waiterId)
            continuation.finish()
        }
        for await snapshot in stream where snapshot == expected {
            return true
        }
        return false
    }
}

@MainActor
private final class PullRequestDemandSurfaceManager: WorkspaceSurfaceManaging {
    private let cwdChanges = AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { continuation in
        continuation.finish()
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { cwdChanges }

    func syncFocus(activeSurfaceId: UUID?) {}

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        .failure(.ghosttyNotInitialized)
    }

    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? { nil }
    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {}
    func undoClose() -> ManagedSurface? { nil }
    func requeueUndo(_ surfaceId: UUID) {}
    func destroy(_ surfaceId: UUID) {}
}
