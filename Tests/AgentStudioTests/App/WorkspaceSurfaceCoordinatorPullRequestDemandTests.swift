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
@Suite("WorkspaceSurfaceCoordinator pull request demand", .serialized)
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
            let coordinator = WorkspaceSurfaceCoordinator(
                store: store,
                viewRegistry: ViewRegistry(),
                runtime: SessionRuntime(store: store),
                surfaceManager: PullRequestDemandSurfaceManager(),
                runtimeRegistry: RuntimeRegistry(),
                paneEventBus: EventBus<RuntimeEnvelope>(),
                filesystemSource: source,
                windowLifecycleStore: windowLifecycle,
                bridgePaneAttendance: BridgePaneAttendanceAtom()
            )
            let sidebarWorktreeId = UUIDv7.generate()
            let owningWindowId = UUIDv7.generate()
            coreAtoms.sidebarVisibleWorktreesRuntime.setVisibleWorktreeIds([])
            coordinator.bindPullRequestDemand(toOwningWindowId: owningWindowId)
            #expect(await source.waitForLastSnapshot([]))

            windowLifecycle.recordWindowRegistered(owningWindowId)
            windowLifecycle.recordWindowPresentation(
                WindowPresentationFacts(isVisible: true, isMiniaturized: false, isOccluded: false),
                for: owningWindowId
            )
            #expect(await source.waitForLastSnapshot([firstWorktree.id]))

            coreAtoms.sidebarVisibleWorktreesRuntime.setVisibleWorktreeIds([sidebarWorktreeId])
            #expect(await source.waitForLastSnapshot([firstWorktree.id, sidebarWorktreeId]))
            let snapshotCountBeforeDuplicate = await source.snapshotCount
            coreAtoms.sidebarVisibleWorktreesRuntime.setVisibleWorktreeIds([sidebarWorktreeId])
            for _ in 0..<20 { await Task.yield() }
            #expect(await source.snapshotCount == snapshotCountBeforeDuplicate)

            store.setActiveTab(secondTab.id)
            #expect(await source.waitForLastSnapshot([secondWorktree.id, sidebarWorktreeId]))

            windowLifecycle.recordWindowPresentation(
                WindowPresentationFacts(isVisible: false, isMiniaturized: false, isOccluded: true),
                for: owningWindowId
            )
            #expect(await source.waitForLastSnapshot([]))

            coreAtoms.sidebarVisibleWorktreesRuntime.setVisibleWorktreeIds([])
            await coordinator.shutdown()
        }
    }

    @Test("demand delivery converges to a reversion matching the in-flight snapshot")
    func demandDeliveryConvergesToInFlightReversion() async throws {
        try await withAsyncTestCoreAtoms { coreAtoms in
            let store = WorkspaceStore()
            let repository = store.addRepo(at: URL(fileURLWithPath: "/tmp/pr-demand-reversion"))
            let worktree = try #require(repository.worktrees.first)
            let pane = store.createPane(
                launchDirectory: worktree.path,
                facets: PaneContextFacets(
                    repoId: repository.id,
                    worktreeId: worktree.id,
                    cwd: worktree.path
                )
            )
            store.appendTab(Tab(paneId: pane.id))

            let source = PullRequestDemandRecordingFilesystemSource()
            let windowLifecycle = WindowLifecycleAtom()
            let coordinator = WorkspaceSurfaceCoordinator(
                store: store,
                viewRegistry: ViewRegistry(),
                runtime: SessionRuntime(store: store),
                surfaceManager: PullRequestDemandSurfaceManager(),
                runtimeRegistry: RuntimeRegistry(),
                paneEventBus: EventBus<RuntimeEnvelope>(),
                filesystemSource: source,
                windowLifecycleStore: windowLifecycle,
                bridgePaneAttendance: BridgePaneAttendanceAtom()
            )
            let owningWindowId = UUIDv7.generate()
            let sidebarWorktreeId = UUIDv7.generate()
            let visiblePaneDemand: Set<UUID> = [worktree.id]
            let intermediateDemand: Set<UUID> = [worktree.id, sidebarWorktreeId]

            coreAtoms.sidebarVisibleWorktreesRuntime.setVisibleWorktreeIds([])
            coordinator.bindPullRequestDemand(toOwningWindowId: owningWindowId)
            #expect(await source.waitForLastSnapshot([]))
            await source.suspendNextSnapshot(visiblePaneDemand)

            windowLifecycle.recordWindowRegistered(owningWindowId)
            windowLifecycle.recordWindowPresentation(
                WindowPresentationFacts(isVisible: true, isMiniaturized: false, isOccluded: false),
                for: owningWindowId
            )
            #expect(await source.waitForLastSnapshot(visiblePaneDemand))

            coreAtoms.sidebarVisibleWorktreesRuntime.setVisibleWorktreeIds([sidebarWorktreeId])
            await eventually("intermediate demand should become pending") {
                coordinator.pendingPullRequestDemandWorktreeIds == intermediateDemand
            }

            coreAtoms.sidebarVisibleWorktreesRuntime.setVisibleWorktreeIds([])
            await eventually("latest demand should replace pending demand even when it matches in-flight") {
                coordinator.pendingPullRequestDemandWorktreeIds == visiblePaneDemand
            }

            await source.releaseSuspendedSnapshot()
            await eventually("demand delivery should settle") {
                coordinator.pullRequestDemandDeliveryTask == nil
            }
            #expect(await source.lastSnapshot == visiblePaneDemand)
            #expect(await source.snapshotCount == 2)

            await coordinator.shutdown()
        }
    }
}

private actor PullRequestDemandRecordingFilesystemSource: WorkspaceFilesystemSourceManaging {
    private var demandSnapshots: [Set<UUID>] = []
    private var demandWaiters: [(Set<UUID>, CheckedContinuation<Void, Never>)] = []
    private var suspendedSnapshot: Set<UUID>?
    private var suspendedSnapshotContinuation: CheckedContinuation<Void, Never>?

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
        var remainingWaiters: [(Set<UUID>, CheckedContinuation<Void, Never>)] = []
        for (expectedWorktreeIds, continuation) in demandWaiters {
            if expectedWorktreeIds == worktreeIds {
                continuation.resume()
            } else {
                remainingWaiters.append((expectedWorktreeIds, continuation))
            }
        }
        demandWaiters = remainingWaiters
        if suspendedSnapshot == worktreeIds {
            suspendedSnapshot = nil
            await withCheckedContinuation { continuation in
                suspendedSnapshotContinuation = continuation
            }
        }
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
        await withCheckedContinuation { continuation in
            demandWaiters.append((expected, continuation))
        }
        return true
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
