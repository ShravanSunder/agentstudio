import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
final class WorkspaceCacheCoordinatorTests {

    private func makeWorkspaceStore() -> WorkspaceStore {
        let tempDir = FileManager.default.temporaryDirectory.appending(
            path: "workspace-cache-coordinator-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        return WorkspaceStore(persistor: persistor)
    }

    @Test
    func topology_repoDiscovered_addsRepoToWorkspaceStore() {
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            cacheStore: cacheStore
        )

        let repoPath = URL(fileURLWithPath: "/tmp/luna-repo")
        let envelope = SystemEnvelope.test(
            event: .topology(.repoDiscovered(repoPath: repoPath, parentPath: repoPath.deletingLastPathComponent()))
        )

        coordinator.handleTopology(envelope)

        #expect(workspaceStore.repos.contains(where: { $0.repoPath == repoPath }))
    }

    @Test
    func topology_worktreeRegistered_unknownRepo_isIgnored() {
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            cacheStore: cacheStore
        )

        let repoCountBefore = workspaceStore.repos.count
        let envelope = SystemEnvelope.test(
            event: .topology(
                .worktreeRegistered(
                    worktreeId: UUID(),
                    repoId: UUID(),
                    rootPath: URL(fileURLWithPath: "/tmp/unknown-repo")
                )
            )
        )

        coordinator.handleTopology(envelope)

        #expect(workspaceStore.repos.count == repoCountBefore)
    }

    @Test
    func topology_repoDiscovered_duplicatePath_doesNotDuplicateRepo() {
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            cacheStore: cacheStore
        )

        let repoPath = URL(fileURLWithPath: "/tmp/luna-duplicate-repo")
        let envelope = SystemEnvelope.test(
            event: .topology(.repoDiscovered(repoPath: repoPath, parentPath: repoPath.deletingLastPathComponent()))
        )

        coordinator.handleTopology(envelope)
        coordinator.handleTopology(envelope)

        #expect(workspaceStore.repos.count == 1)
    }

    @Test
    func topology_worktreeUnregistered_unknownRepo_isIgnored() {
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            cacheStore: cacheStore
        )

        let envelope = SystemEnvelope.test(
            event: .topology(
                .worktreeUnregistered(
                    worktreeId: UUID(),
                    repoId: UUID()
                )
            )
        )

        coordinator.handleTopology(envelope)

        #expect(workspaceStore.repos.isEmpty)
    }

    @Test
    func enrichment_snapshotChanged_updatesWorktreeCache() {
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            cacheStore: cacheStore
        )

        let repoId = UUID()
        let worktreeId = UUID()
        let snapshot = GitWorkingTreeSnapshot(
            worktreeId: worktreeId,
            repoId: repoId,
            rootPath: URL(fileURLWithPath: "/tmp/repo"),
            summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
            branch: "main"
        )

        let envelope = WorktreeEnvelope.test(
            event: .gitWorkingDirectory(.snapshotChanged(snapshot: snapshot)),
            repoId: repoId,
            worktreeId: worktreeId,
            source: .system(.builtin(.gitWorkingDirectoryProjector))
        )

        coordinator.handleEnrichment(envelope)

        #expect(cacheStore.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "main")
        #expect(cacheStore.worktreeEnrichmentByWorktreeId[worktreeId]?.repoId == repoId)
    }

    @Test
    func enrichment_branchChanged_preservesExistingSnapshot() {
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            cacheStore: cacheStore
        )

        let repoId = UUID()
        let worktreeId = UUID()
        let snapshot = GitWorkingTreeSnapshot(
            worktreeId: worktreeId,
            repoId: repoId,
            rootPath: URL(fileURLWithPath: "/tmp/repo"),
            summary: GitWorkingTreeSummary(changed: 2, staged: 1, untracked: 3),
            branch: "main"
        )
        cacheStore.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: worktreeId,
                repoId: repoId,
                branch: "main",
                snapshot: snapshot
            )
        )

        coordinator.handleEnrichment(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(
                    .branchChanged(worktreeId: worktreeId, repoId: repoId, from: "main", to: "feature/new")
                ),
                repoId: repoId,
                worktreeId: worktreeId,
                source: .system(.builtin(.gitWorkingDirectoryProjector))
            )
        )

        #expect(cacheStore.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "feature/new")
        #expect(cacheStore.worktreeEnrichmentByWorktreeId[worktreeId]?.snapshot == snapshot)
    }

    @Test
    func enrichment_pullRequestCountsChanged_mapsByBranch() {
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            cacheStore: cacheStore
        )

        let repoId = UUID()
        let worktreeId = UUID()
        let otherRepoId = UUID()
        let otherWorktreeId = UUID()
        cacheStore.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: worktreeId,
                repoId: repoId,
                branch: "feature/runtime"
            )
        )
        cacheStore.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: otherWorktreeId,
                repoId: otherRepoId,
                branch: "feature/runtime"
            )
        )

        let envelope = WorktreeEnvelope.test(
            event: .forge(.pullRequestCountsChanged(repoId: repoId, countsByBranch: ["feature/runtime": 3])),
            repoId: repoId,
            worktreeId: nil,
            source: .system(.service(.gitForge(provider: "github")))
        )

        coordinator.handleEnrichment(envelope)

        #expect(cacheStore.pullRequestCountByWorktreeId[worktreeId] == 3)
        #expect(cacheStore.pullRequestCountByWorktreeId[otherWorktreeId] == nil)
    }

    @Test
    func enrichment_originChanged_validRemoteDerivesResolvedIdentity() {
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            cacheStore: cacheStore
        )

        let repo = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/luna-origin-identity"))

        coordinator.handleEnrichment(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(
                    .originChanged(
                        repoId: repo.id,
                        from: "",
                        to: "git@github.com:askluna/agent-studio.git"
                    )
                ),
                repoId: repo.id,
                source: .system(.builtin(.gitWorkingDirectoryProjector))
            )
        )

        guard case .some(.resolved(_, let raw, let identity, _)) = cacheStore.repoEnrichmentByRepoId[repo.id] else {
            Issue.record("Expected resolved enrichment")
            return
        }
        #expect(raw.origin == "git@github.com:askluna/agent-studio.git")
        #expect(identity.groupKey == "remote:askluna/agent-studio")
        #expect(identity.remoteSlug == "askluna/agent-studio")
        #expect(identity.organizationName == "askluna")
        #expect(identity.displayName == "agent-studio")
    }

    @Test
    func enrichment_originChanged_emptyOriginDerivesLocalIdentity() {
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            cacheStore: cacheStore
        )

        let repo = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/MyProject"))

        coordinator.handleEnrichment(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(
                    .originChanged(
                        repoId: repo.id,
                        from: "",
                        to: ""
                    )
                ),
                repoId: repo.id,
                source: .system(.builtin(.gitWorkingDirectoryProjector))
            )
        )

        guard case .some(.resolved(_, let raw, let identity, _)) = cacheStore.repoEnrichmentByRepoId[repo.id] else {
            Issue.record("Expected resolved local enrichment")
            return
        }
        #expect(raw.origin == nil)
        #expect(identity.groupKey == "local:MyProject")
        #expect(identity.remoteSlug == nil)
    }

    @Test
    func scopeSync_originChanged_registersAndRepoRemoved_unregisters() async {
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let recordedScopeChanges = RecordedScopeChanges()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            cacheStore: cacheStore,
            scopeSyncHandler: { change in
                await recordedScopeChanges.record(change)
            }
        )

        let repoPath = URL(fileURLWithPath: "/tmp/luna-scope-repo")
        let repo = workspaceStore.addRepo(at: repoPath)
        let worktree = Worktree(name: "main", path: repoPath, branch: "main", isMainWorktree: true)
        workspaceStore.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])

        coordinator.handleEnrichment(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(
                    .originChanged(
                        repoId: repo.id,
                        from: "",
                        to: "git@github.com:askluna/agent-studio.git"
                    )
                ),
                repoId: repo.id,
                worktreeId: worktree.id,
                source: .system(.builtin(.gitWorkingDirectoryProjector))
            )
        )

        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(.repoRemoved(repoPath: repoPath))
            )
        )

        let completed = await eventually("scope changes should be recorded") {
            let count = await recordedScopeChanges.count
            return count >= 2
        }
        #expect(completed)

        let changes = await recordedScopeChanges.values
        #expect(
            changes.contains {
                if case .registerForgeRepo(let repoId, let remote) = $0 {
                    return repoId == repo.id && remote == "git@github.com:askluna/agent-studio.git"
                }
                return false
            }
        )
        #expect(
            changes.contains {
                if case .unregisterForgeRepo(let repoId) = $0 {
                    return repoId == repo.id
                }
                return false
            }
        )
    }

    @Test
    func integration_addFolderTopologyConvergesToResolvedRemoteIdentity() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let recordedScopeChanges = RecordedScopeChanges()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            cacheStore: cacheStore,
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
            guard case .some(.resolved(_, _, let identity, _)) = cacheStore.repoEnrichmentByRepoId[repo.id] else {
                return false
            }
            return identity.groupKey == "remote:askluna/agent-studio"
        }
        #expect(resolved)

        let scopeSynced = await eventually("scope sync should register forge repo") {
            let changes = await recordedScopeChanges.values
            return changes.contains {
                if case .registerForgeRepo(let repoId, let remote) = $0 {
                    return repoId == repo.id && remote == "git@github.com:askluna/agent-studio.git"
                }
                return false
            }
        }
        #expect(scopeSynced)

        await projector.shutdown()
    }

    @Test
    func integration_addFolderTopologyConvergesToResolvedLocalIdentityWhenRemoteMissing() async {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let recordedScopeChanges = RecordedScopeChanges()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            cacheStore: cacheStore,
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
                    origin: nil
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
            guard case .some(.resolved(_, let raw, let identity, _)) = cacheStore.repoEnrichmentByRepoId[repo.id]
            else {
                return false
            }
            return raw.origin == nil && identity.groupKey == "local:\(repo.name)"
        }
        #expect(resolved)

        let scopeSynced = await eventually("scope sync should unregister forge repo for local-only repo") {
            let changes = await recordedScopeChanges.values
            return changes.contains {
                if case .unregisterForgeRepo(let repoId) = $0 {
                    return repoId == repo.id
                }
                return false
            }
        }
        #expect(scopeSynced)

        await projector.shutdown()
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
