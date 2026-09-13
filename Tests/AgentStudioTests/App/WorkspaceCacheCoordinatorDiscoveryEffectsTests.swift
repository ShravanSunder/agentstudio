import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct WorkspaceCacheCoordinatorDiscoveryEffectsTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("not-scanned discovery followed by an authoritative scan registers the new main worktree once")
    func notScannedThenScannedDiscoveryRegistersNewMainWorktreeOnce() async throws {
        try await withDiscoveryHarness { harness in
            let repoPath = URL(
                filePath: "/tmp/discovery-effects-single-\(UUIDv7.generate().uuidString)"
            )

            harness.cacheCoordinator.handleTopology(
                discoveryEnvelope(repoPath: repoPath, linkedWorktrees: .notScanned)
            )
            await harness.surfaceCoordinator.waitForFilesystemRootsAndActivitySyncIdle()

            let mainWorktree = try #require(harness.store.repos.single?.worktrees.single)
            #expect(mainWorktree.isMainWorktree)
            #expect(mainWorktree.path == repoPath.standardizedFileURL)

            harness.cacheCoordinator.handleTopology(
                discoveryEnvelope(repoPath: repoPath, linkedWorktrees: .scanned([]))
            )
            await harness.surfaceCoordinator.waitForFilesystemRootsAndActivitySyncIdle()

            let registrationIds = await harness.filesystemSource.operations().compactMap(\.registeredWorktreeId)
            #expect(registrationIds == [mainWorktree.id])
            #expect(await harness.filesystemSource.snapshot().registeredRoots == [mainWorktree.id: repoPath])
        }
    }

    @Test("batched discovery registers both new main worktrees once and replay emits no duplicates")
    func batchedDiscoveryRegistersBothMainWorktreesWithoutReplayDuplicates() async throws {
        try await withDiscoveryHarness { harness in
            let parentPath = URL(
                filePath: "/tmp/discovery-effects-batch-\(UUIDv7.generate().uuidString)"
            )
            let firstRepoPath = parentPath.appending(path: "first")
            let secondRepoPath = parentPath.appending(path: "second")
            let repositories = [
                DiscoveredRepoTopologyInfo(repoPath: firstRepoPath, linkedWorktrees: .scanned([])),
                DiscoveredRepoTopologyInfo(repoPath: secondRepoPath, linkedWorktrees: .scanned([])),
            ]
            let envelope = SystemEnvelope.test(
                event: .topology(
                    .reposDiscovered(parentPath: parentPath, repositories: repositories)
                ),
                eventId: UUIDv7.generate()
            )

            harness.cacheCoordinator.handleTopology(envelope)
            await harness.surfaceCoordinator.waitForFilesystemRootsAndActivitySyncIdle()

            let discoveredMainWorktrees = try harness.store.repos.map { repo in
                try #require(repo.worktrees.single)
            }
            let expectedWorktreeIds = Set(discoveredMainWorktrees.map(\.id))
            let expectedPaths = Set([firstRepoPath.standardizedFileURL, secondRepoPath.standardizedFileURL])
            #expect(Set(discoveredMainWorktrees.map(\.path)) == expectedPaths)
            #expect(Set(await harness.filesystemSource.snapshot().registeredRoots.keys) == expectedWorktreeIds)

            harness.cacheCoordinator.handleTopology(envelope)
            await harness.surfaceCoordinator.waitForFilesystemRootsAndActivitySyncIdle()

            let registrationIds = await harness.filesystemSource.operations().compactMap(\.registeredWorktreeId)
            #expect(registrationIds.count == 2)
            #expect(Set(registrationIds) == expectedWorktreeIds)
        }
    }

    private func discoveryEnvelope(
        repoPath: URL,
        linkedWorktrees: LinkedWorktreeInfo
    ) -> SystemEnvelope {
        SystemEnvelope.test(
            event: .topology(
                .repoDiscovered(
                    repoPath: repoPath,
                    parentPath: repoPath.deletingLastPathComponent(),
                    linkedWorktrees: linkedWorktrees
                )
            ),
            eventId: UUIDv7.generate()
        )
    }

    private func withDiscoveryHarness(
        operation: (DiscoveryEffectsHarness) async throws -> Void
    ) async throws {
        let harness = makeDiscoveryHarness()
        do {
            try await operation(harness)
        } catch {
            await harness.surfaceCoordinator.shutdown()
            throw error
        }
        await harness.surfaceCoordinator.shutdown()
    }

    private func makeDiscoveryHarness() -> DiscoveryEffectsHarness {
        let store = WorkspaceStore()
        let filesystemSource = OrderedRecordingFilesystemSource()
        let gitStatusPhysicalGate = AgentStudioGitStatusPhysicalGate()
        let surfaceCoordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: MockFilesystemCoordinatorSurfaceManager(),
            runtimeRegistry: RuntimeRegistry(),
            paneEventBus: EventBus<RuntimeEnvelope>(),
            gitWorkingTreeStatusProvider: StubGitWorkingTreeStatusProvider { _ in nil },
            gitStatusPhysicalGate: gitStatusPhysicalGate,
            filesystemSource: filesystemSource,
            windowLifecycleStore: WindowLifecycleAtom(),
            bridgePaneAttendance: BridgePaneAttendanceAtom()
        )
        let cacheCoordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: store,
            repoCache: RepoCacheAtom(),
            welcomeAtom: WelcomeAtom(),
            topologyEffectHandler: surfaceCoordinator,
            scopeSyncHandler: { _ in }
        )
        return DiscoveryEffectsHarness(
            store: store,
            filesystemSource: filesystemSource,
            surfaceCoordinator: surfaceCoordinator,
            cacheCoordinator: cacheCoordinator
        )
    }
}

@MainActor
private struct DiscoveryEffectsHarness {
    let store: WorkspaceStore
    let filesystemSource: OrderedRecordingFilesystemSource
    let surfaceCoordinator: WorkspaceSurfaceCoordinator
    let cacheCoordinator: WorkspaceCacheCoordinator
}
