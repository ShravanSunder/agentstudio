import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
final class WorkspaceCacheCoordinatorIntegrationTests {

    private func makeWorkspaceStore() -> WorkspaceStore {
        let tempDir = FileManager.default.temporaryDirectory.appending(
            path: "workspace-cache-coordinator-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        return WorkspaceStore(persistor: persistor)
    }

    // MARK: - Integration: Add Folder Convergence

    @Test
    func integration_addFolderTopologyConvergesToResolvedRemoteIdentity() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let recordedScopeChanges = RecordedScopeChanges()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { change in
                await recordedScopeChanges.record(change)
            }
        )
        let projector = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: .stub { _ in
                GitWorkingTreeStatus(
                    summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                    branch: "main",
                    origin: "git@github.com:askluna/agent-studio.git"
                )
            },
            coalescingWindow: .zero
        )

        coordinator.startConsuming()
        await projector.start()
        defer {
            coordinator.stopConsuming()
        }

        let repoPath = URL(fileURLWithPath: "/tmp/luna-converge-remote")
        let repo = workspaceStore.addRepo(at: repoPath)
        let worktreeId = UUID()
        let posted = await bus.post(
            .system(
                SystemEnvelope.test(
                    event: .topology(
                        .worktreeRegistered(worktreeId: worktreeId, repoId: repo.id, rootPath: repoPath)
                    ),
                    source: .builtin(.filesystemWatcher)
                )
            )
        )
        #expect(posted.subscriberCount > 0)

        let resolved = await eventually("repo enrichment should resolve from projector origin") {
            guard case .some(.resolvedRemote(_, _, let identity, _)) = repoCache.repoEnrichmentByRepoId[repo.id] else {
                return false
            }
            return identity.groupKey == "remote:askluna/agent-studio"
        }
        #expect(resolved)

        let scopeSynced = await eventually("scope sync should not register forge repo for origin event path") {
            let changes = await recordedScopeChanges.values
            return changes.isEmpty
        }
        #expect(scopeSynced)

        await projector.shutdown()
    }

    @Test
    func integration_addFolderTopologyConvergesToResolvedLocalIdentityWhenRemoteMissing() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let recordedScopeChanges = RecordedScopeChanges()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { change in
                await recordedScopeChanges.record(change)
            }
        )
        let projector = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: .stub { _ in
                GitWorkingTreeStatus(
                    summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                    branch: "main",
                    originResolution: .confirmedAbsent
                )
            },
            coalescingWindow: .zero
        )

        coordinator.startConsuming()
        await projector.start()
        defer {
            coordinator.stopConsuming()
        }

        let repoPath = URL(fileURLWithPath: "/tmp/luna-converge-local")
        let repo = workspaceStore.addRepo(at: repoPath)
        let worktreeId = UUID()
        _ = await bus.post(
            .system(
                SystemEnvelope.test(
                    event: .topology(
                        .worktreeRegistered(worktreeId: worktreeId, repoId: repo.id, rootPath: repoPath)
                    ),
                    source: .builtin(.filesystemWatcher)
                )
            )
        )

        let resolved = await eventually("local-only repo enrichment should resolve") {
            guard case .some(.resolvedLocal(_, let identity, _)) = repoCache.repoEnrichmentByRepoId[repo.id]
            else {
                return false
            }
            return identity.groupKey == "local:\(repo.name)"
        }
        #expect(resolved)

        let scopeSynced = await eventually("scope sync should remain empty for local-only origin event path") {
            let changes = await recordedScopeChanges.values
            return changes.isEmpty
        }
        #expect(scopeSynced)

        await projector.shutdown()
    }

    // MARK: - User-Initiated Repo Removal

    @Test
    func removeRepo_cleansUpCacheAndForgeScope() async {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let recordedScopeChanges = RecordedScopeChanges()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { change in
                await recordedScopeChanges.record(change)
            }
        )

        let repoPath = URL(fileURLWithPath: "/tmp/removal-test-repo")
        let repo = workspaceStore.addRepo(at: repoPath)
        let worktreeId = repo.worktrees.first!.id

        // Seed cache with enrichment data
        repoCache.setRepoEnrichment(.awaitingOrigin(repoId: repo.id))
        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktreeId, repoId: repo.id, branch: "main")
        )
        repoCache.setPullRequestCount(3, for: worktreeId)

        // User-initiated removal
        coordinator.handleRepoRemoval(repoId: repo.id)

        // Repo should be hard-deleted from store
        #expect(workspaceStore.repos.isEmpty)

        // All cache entries should be pruned
        #expect(repoCache.repoEnrichmentByRepoId[repo.id] == nil)
        #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId] == nil)
        #expect(repoCache.pullRequestCountByWorktreeId[worktreeId] == nil)

        // Forge scope should be unregistered
        let converged = await eventually("forge unregister should fire") {
            let changes = await recordedScopeChanges.values
            return changes.contains {
                if case .unregisterForgeRepo(let id) = $0 { return id == repo.id }
                return false
            }
        }
        #expect(converged)
    }

    // MARK: - Lifecycle Integration

    @Test
    func integration_fullRepoLifecycle_addEnrichRemove() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let recordedScopeChanges = RecordedScopeChanges()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { change in
                await recordedScopeChanges.record(change)
            }
        )
        let projector = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: .stub { _ in
                GitWorkingTreeStatus(
                    summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                    branch: "main",
                    origin: "git@github.com:askluna/agent-studio.git"
                )
            },
            coalescingWindow: .zero
        )

        coordinator.startConsuming()
        await projector.start()
        defer {
            coordinator.stopConsuming()
        }

        // Phase 1: Discover repo
        let repoPath = URL(fileURLWithPath: "/tmp/lifecycle-test-repo")
        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(
                    .repoDiscovered(repoPath: repoPath, parentPath: repoPath.deletingLastPathComponent())
                )
            )
        )
        #expect(workspaceStore.repos.count == 1)
        let repo = workspaceStore.repos[0]

        // Phase 2: Register worktree → triggers enrichment via projector
        let worktreeId = UUID()
        _ = await bus.post(
            .system(
                SystemEnvelope.test(
                    event: .topology(
                        .worktreeRegistered(worktreeId: worktreeId, repoId: repo.id, rootPath: repoPath)
                    ),
                    source: .builtin(.filesystemWatcher)
                )
            )
        )

        let enriched = await eventually("enrichment should resolve") {
            guard case .some(.resolvedRemote(_, _, let identity, _)) = repoCache.repoEnrichmentByRepoId[repo.id] else {
                return false
            }
            return identity.groupKey == "remote:askluna/agent-studio"
        }
        #expect(enriched)
        #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "main")

        // Phase 3: User removes repo
        coordinator.handleRepoRemoval(repoId: repo.id)

        // Repo gone
        #expect(workspaceStore.repos.isEmpty)

        // Cache fully pruned
        #expect(repoCache.repoEnrichmentByRepoId[repo.id] == nil)
        #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId] == nil)

        // Forge unregistered
        let unregistered = await eventually("forge unregister should fire") {
            let changes = await recordedScopeChanges.values
            return changes.contains {
                if case .unregisterForgeRepo(let id) = $0 { return id == repo.id }
                return false
            }
        }
        #expect(unregistered)

        await projector.shutdown()
    }

    @Test
    func integration_unavailableRepoReAdd_clearsUnavailableState() async {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )

        // Setup: add repo, mark unavailable (simulating filesystem disappearance)
        let repoPath = URL(fileURLWithPath: "/tmp/re-add-test-repo")
        let repo = workspaceStore.addRepo(at: repoPath)
        workspaceStore.markRepoUnavailable(repo.id)
        #expect(workspaceStore.isRepoUnavailable(repo.id))

        // User re-adds the same path
        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(
                    .repoDiscovered(repoPath: repoPath, parentPath: repoPath.deletingLastPathComponent())
                )
            )
        )

        // Should be available again, same ID, enrichment seeded
        #expect(!workspaceStore.isRepoUnavailable(repo.id))
        #expect(workspaceStore.repos.count == 1)
        #expect(workspaceStore.repos[0].id == repo.id)
        #expect(repoCache.repoEnrichmentByRepoId[repo.id] == .awaitingOrigin(repoId: repo.id))
    }

    // MARK: - Watched Folder Scope Change

    @Test
    func scopeSync_updateWatchedFolders_forwardsToHandler() async {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let recordedScopeChanges = RecordedScopeChanges()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { change in
                await recordedScopeChanges.record(change)
            }
        )

        await coordinator.syncScope(
            .updateWatchedFolders(paths: [URL(fileURLWithPath: "/projects")])
        )

        let changes = await recordedScopeChanges.values
        #expect(changes.count == 1)
        if case .updateWatchedFolders(let paths) = changes.first {
            #expect(paths.count == 1)
            #expect(paths[0].path == "/projects")
        } else {
            Issue.record("Expected updateWatchedFolders scope change")
        }
    }

    // MARK: - Bus Pathway Tests

    @Test
    func topology_repoDiscoveredViaBus_processedBySubscription() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        coordinator.startConsuming()
        defer { coordinator.stopConsuming() }

        // Wait for subscription Task to actually subscribe to the bus
        await waitForSubscriber(bus: bus)

        let repoPath = URL(fileURLWithPath: "/tmp/bus-topology-test")
        let postResult = await bus.post(
            .system(
                SystemEnvelope.test(
                    event: .topology(
                        .repoDiscovered(
                            repoPath: repoPath,
                            parentPath: repoPath.deletingLastPathComponent()
                        )
                    ),
                    source: .builtin(.filesystemWatcher)
                )
            )
        )
        #expect(postResult.subscriberCount > 0)

        let converged = await eventually("repo should appear via bus subscription") {
            workspaceStore.repos.contains { $0.repoPath == repoPath }
        }
        #expect(converged)
        #expect(workspaceStore.repos.count == 1)
    }

    @Test
    func topology_bootReplayAndRescan_idempotentViaBus() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        coordinator.startConsuming()
        defer { coordinator.stopConsuming() }

        // Wait for subscription Task to actually subscribe to the bus
        await waitForSubscriber(bus: bus)

        let repoPath = URL(fileURLWithPath: "/tmp/boot-rescan-dedup")

        // Simulate boot replay posting .repoDiscovered
        await bus.post(
            .system(
                SystemEnvelope.test(
                    event: .topology(
                        .repoDiscovered(repoPath: repoPath, parentPath: repoPath.deletingLastPathComponent())
                    ),
                    source: .builtin(.coordinator)
                )
            )
        )

        let bootConverged = await eventually("boot replay should add repo") {
            workspaceStore.repos.count == 1
        }
        #expect(bootConverged)

        // Simulate FSEvents rescan posting the same .repoDiscovered
        await bus.post(
            .system(
                SystemEnvelope.test(
                    event: .topology(
                        .repoDiscovered(repoPath: repoPath, parentPath: repoPath.deletingLastPathComponent())
                    ),
                    source: .builtin(.filesystemWatcher)
                )
            )
        )

        // Allow processing
        try? await Task.sleep(for: .milliseconds(50))

        // Should still be exactly 1 repo — idempotent
        #expect(workspaceStore.repos.count == 1)
    }

    // MARK: - Helpers

    /// Polls the bus until at least one subscriber is registered, ensuring the
    /// coordinator's `startConsuming()` Task has completed its `subscribe()` call.
    private func waitForSubscriber(bus: EventBus<RuntimeEnvelope>, maxAttempts: Int = 50) async {
        for _ in 0..<maxAttempts {
            if await bus.subscriberCount > 0 { return }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func eventually(
        _ description: String,
        maxAttempts: Int = 100,
        pollIntervalNanoseconds: UInt64 = 10_000_000,
        condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        for _ in 0..<maxAttempts {
            if await condition() {
                return true
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        Issue.record("\(description) timed out")
        return false
    }
}

private actor RecordedScopeChanges {
    private var scopeChanges: [ScopeChange] = []

    func record(_ change: ScopeChange) {
        scopeChanges.append(change)
    }

    var count: Int {
        scopeChanges.count
    }

    var values: [ScopeChange] {
        scopeChanges
    }
}
