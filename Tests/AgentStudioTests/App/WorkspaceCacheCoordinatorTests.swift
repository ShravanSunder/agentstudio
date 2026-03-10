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
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )

        let repoPath = URL(fileURLWithPath: "/tmp/luna-repo")
        let envelope = SystemEnvelope.test(
            event: .topology(.repoDiscovered(repoPath: repoPath, parentPath: repoPath.deletingLastPathComponent()))
        )

        coordinator.handleTopology(envelope)

        guard let repo = workspaceStore.repos.first(where: { $0.repoPath == repoPath }) else {
            Issue.record("Expected discovered repo to be added")
            return
        }
        #expect(repoCache.repoEnrichmentByRepoId[repo.id] == .awaitingOrigin(repoId: repo.id))
    }

    @Test
    func topology_worktreeRegistered_unknownRepo_isIgnored() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
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
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
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
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
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
    func topology_worktreeUnregistered_prunesWorktreeCaches() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )

        let repoPath = URL(fileURLWithPath: "/tmp/luna-unregister-prune")
        let repo = workspaceStore.addRepo(at: repoPath)
        guard let worktreeId = workspaceStore.repos.first(where: { $0.id == repo.id })?.worktrees.first?.id else {
            Issue.record("Expected repo to have a main worktree")
            return
        }

        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: worktreeId,
                repoId: repo.id,
                branch: "main"
            )
        )
        repoCache.setPullRequestCount(5, for: worktreeId)
        repoCache.setNotificationCount(2, for: worktreeId)

        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(
                    .worktreeUnregistered(worktreeId: worktreeId, repoId: repo.id)
                )
            )
        )

        #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId] == nil)
        #expect(repoCache.pullRequestCountByWorktreeId[worktreeId] == nil)
        #expect(repoCache.notificationCountByWorktreeId[worktreeId] == nil)
    }

    @Test
    func enrichment_snapshotChanged_updatesWorktreeCache() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
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

        #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "main")
        #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.repoId == repoId)
    }

    @Test
    func enrichment_branchChanged_preservesExistingSnapshot() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
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
        repoCache.setWorktreeEnrichment(
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

        #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "feature/new")
        #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.snapshot == snapshot)
    }

    @Test
    func enrichment_pullRequestCountsChanged_mapsByBranch() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )

        let repoId = UUID()
        let worktreeId = UUID()
        let otherRepoId = UUID()
        let otherWorktreeId = UUID()
        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: worktreeId,
                repoId: repoId,
                branch: "feature/runtime"
            )
        )
        repoCache.setWorktreeEnrichment(
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

        #expect(repoCache.pullRequestCountByWorktreeId[worktreeId] == 3)
        #expect(repoCache.pullRequestCountByWorktreeId[otherWorktreeId] == nil)
    }

    @Test
    func enrichment_originChanged_validRemoteDerivesResolvedIdentity() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
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

        guard case .some(.resolvedRemote(_, let raw, let identity, _)) = repoCache.repoEnrichmentByRepoId[repo.id] else {
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
    func enrichment_originChanged_emptyOriginDoesNotResolveLocalIdentity() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )

        let repo = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/luna-empty-origin"))
        repoCache.setRepoEnrichment(.awaitingOrigin(repoId: repo.id))

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

        #expect(repoCache.repoEnrichmentByRepoId[repo.id] == .awaitingOrigin(repoId: repo.id))
    }

    @Test
    func enrichment_originUnavailableDerivesLocalIdentity() {
        let workspaceStore = makeWorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )

        let repo = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/MyProject"))

        coordinator.handleEnrichment(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(
                    .originUnavailable(repoId: repo.id)
                ),
                repoId: repo.id,
                source: .system(.builtin(.gitWorkingDirectoryProjector))
            )
        )

        guard case .some(.resolvedLocal(_, let identity, _)) = repoCache.repoEnrichmentByRepoId[repo.id] else {
            Issue.record("Expected resolved local enrichment")
            return
        }
        #expect(repoCache.repoEnrichmentByRepoId[repo.id]?.raw?.origin == nil)
        #expect(identity.groupKey == "local:MyProject")
        #expect(identity.remoteSlug == nil)
    }

    @Test
    func scopeSync_originAndBranchDoNotInvokeForgeCommands_repoRemoved_unregisters() async {
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

        let repoPath = URL(fileURLWithPath: "/tmp/luna-scope-repo")
        let repo = workspaceStore.addRepo(at: repoPath)
        let worktree = Worktree(repoId: repo.id, name: "main", path: repoPath, isMainWorktree: true)
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

        coordinator.handleEnrichment(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(
                    .branchChanged(
                        worktreeId: worktree.id,
                        repoId: repo.id,
                        from: "main",
                        to: "feature/runtime"
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
            return count >= 1
        }
        #expect(completed)

        let changes = await recordedScopeChanges.values
        #expect(
            changes.contains {
                if case .unregisterForgeRepo(let repoId) = $0 {
                    return repoId == repo.id
                }
                return false
            }
        )
        #expect(
            changes.contains {
                if case .registerForgeRepo = $0 { return true }
                return false
            } == false
        )
        #expect(
            changes.contains {
                if case .refreshForgeRepo = $0 { return true }
                return false
            } == false
        )
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
