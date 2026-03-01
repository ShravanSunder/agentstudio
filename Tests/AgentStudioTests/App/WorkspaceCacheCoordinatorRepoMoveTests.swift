import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct WorkspaceCacheCoordinatorRepoMoveTests {
    private func makeWorkspaceStore() -> WorkspaceStore {
        let tempDir = FileManager.default.temporaryDirectory.appending(
            path: "workspace-cache-coordinator-repo-move-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        return WorkspaceStore(persistor: persistor)
    }

    @Test("repoRemoved marks panes orphaned and prunes cache while preserving canonical identities")
    func repoRemovedOrphansPanesAndPreservesRepoIdentity() {
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            cacheStore: cacheStore
        )

        let repoPath = URL(fileURLWithPath: "/tmp/repo-move-test")
        let repo = workspaceStore.addRepo(at: repoPath)
        let mainWorktree = Worktree(
            name: "main",
            path: repoPath,
            branch: "main",
            isMainWorktree: true
        )
        workspaceStore.reconcileDiscoveredWorktrees(repo.id, worktrees: [mainWorktree])
        let persistedMainWorktreeId = workspaceStore.repos[0].worktrees[0].id

        let pane = workspaceStore.createPane(
            source: .worktree(worktreeId: persistedMainWorktreeId, repoId: repo.id)
        )

        cacheStore.setRepoEnrichment(
            .resolved(
                repoId: repo.id,
                raw: RawRepoOrigin(origin: "git@github.com:acme/repo.git", upstream: nil),
                identity: RepoIdentity(
                    groupKey: "remote:acme/repo",
                    remoteSlug: "acme/repo",
                    organizationName: "acme",
                    displayName: "repo"
                ),
                updatedAt: Date()
            )
        )
        cacheStore.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: persistedMainWorktreeId,
                repoId: repo.id,
                branch: "main"
            )
        )

        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(.repoRemoved(repoPath: repoPath))
            )
        )

        #expect(workspaceStore.repos.count == 1)
        #expect(workspaceStore.repos[0].id == repo.id)
        #expect(workspaceStore.isRepoUnavailable(repo.id))
        #expect(cacheStore.repoEnrichmentByRepoId[repo.id] == nil)
        #expect(cacheStore.worktreeEnrichmentByWorktreeId[persistedMainWorktreeId] == nil)
        #expect(cacheStore.pullRequestCountByWorktreeId[persistedMainWorktreeId] == nil)
        #expect(cacheStore.notificationCountByWorktreeId[persistedMainWorktreeId] == nil)
        #expect(
            workspaceStore.pane(pane.id)?.residency
                == .orphaned(reason: .worktreeNotFound(path: repoPath.path))
        )
    }

    @Test("re-association preserves UUID links and restores orphaned pane residency")
    func relocateRepoPreservesIdentity() {
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            cacheStore: cacheStore
        )

        let oldRepoPath = URL(fileURLWithPath: "/tmp/repo-move-old")
        let repo = workspaceStore.addRepo(at: oldRepoPath)
        let oldWorktree = Worktree(
            name: "main",
            path: oldRepoPath,
            branch: "main",
            isMainWorktree: true
        )
        workspaceStore.reconcileDiscoveredWorktrees(repo.id, worktrees: [oldWorktree])
        let previousWorktreeId = workspaceStore.repos[0].worktrees[0].id

        let pane = workspaceStore.createPane(
            source: .worktree(worktreeId: previousWorktreeId, repoId: repo.id)
        )
        workspaceStore.appendTab(Tab(paneId: pane.id))

        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(.repoRemoved(repoPath: oldRepoPath))
            )
        )
        #expect(workspaceStore.pane(pane.id)?.residency.isOrphaned == true)

        let relocatedPath = URL(fileURLWithPath: "/tmp/repo-move-new")
        let discoveredAtNewPath = Worktree(
            name: "main",
            path: relocatedPath,
            branch: "main",
            isMainWorktree: true
        )

        let reassociated = coordinator.reassociateRepo(
            repoId: repo.id,
            to: relocatedPath,
            discoveredWorktrees: [discoveredAtNewPath]
        )

        #expect(reassociated)
        #expect(workspaceStore.isRepoUnavailable(repo.id) == false)
        #expect(workspaceStore.repos[0].repoPath == relocatedPath)
        #expect(workspaceStore.repos[0].worktrees.count == 1)
        #expect(workspaceStore.repos[0].worktrees[0].id == previousWorktreeId)
        #expect(workspaceStore.repos[0].worktrees[0].path == relocatedPath)
        #expect(workspaceStore.pane(pane.id)?.residency == .active)
    }

    @Test("repo rediscovery at same path clears unavailable state and restores orphaned panes")
    func rediscoveryAtSamePathRestoresRepoAvailability() {
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            cacheStore: cacheStore
        )

        let repoPath = URL(fileURLWithPath: "/tmp/repo-rediscovery")
        let repo = workspaceStore.addRepo(at: repoPath)
        let worktree = Worktree(
            name: "main",
            path: repoPath,
            branch: "main",
            isMainWorktree: true
        )
        workspaceStore.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        let worktreeId = workspaceStore.repos[0].worktrees[0].id

        let pane = workspaceStore.createPane(source: .worktree(worktreeId: worktreeId, repoId: repo.id))
        workspaceStore.appendTab(Tab(paneId: pane.id))

        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(.repoRemoved(repoPath: repoPath))
            )
        )
        #expect(workspaceStore.isRepoUnavailable(repo.id))
        #expect(workspaceStore.pane(pane.id)?.residency.isOrphaned == true)

        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(.repoDiscovered(repoPath: repoPath, parentPath: repoPath.deletingLastPathComponent()))
            )
        )

        #expect(workspaceStore.isRepoUnavailable(repo.id) == false)
        #expect(workspaceStore.pane(pane.id)?.residency == .active)
    }

    @Test("re-association restores non-layout orphaned panes as backgrounded")
    func reassociationRestoresBackgroundedResidencyForNonLayoutPanes() {
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            cacheStore: cacheStore
        )

        let oldRepoPath = URL(fileURLWithPath: "/tmp/repo-move-backgrounded-old")
        let repo = workspaceStore.addRepo(at: oldRepoPath)
        let oldWorktree = Worktree(
            name: "main",
            path: oldRepoPath,
            branch: "main",
            isMainWorktree: true
        )
        workspaceStore.reconcileDiscoveredWorktrees(repo.id, worktrees: [oldWorktree])
        let worktreeId = workspaceStore.repos[0].worktrees[0].id

        let pane = workspaceStore.createPane(
            source: .worktree(worktreeId: worktreeId, repoId: repo.id)
        )
        let tab = Tab(paneId: pane.id)
        workspaceStore.appendTab(tab)
        workspaceStore.backgroundPane(pane.id)
        #expect(workspaceStore.pane(pane.id)?.residency == .backgrounded)

        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(.repoRemoved(repoPath: oldRepoPath))
            )
        )
        #expect(workspaceStore.pane(pane.id)?.residency.isOrphaned == true)

        let relocatedPath = URL(fileURLWithPath: "/tmp/repo-move-backgrounded-new")
        let discoveredAtNewPath = Worktree(
            name: "main",
            path: relocatedPath,
            branch: "main",
            isMainWorktree: true
        )
        let reassociated = coordinator.reassociateRepo(
            repoId: repo.id,
            to: relocatedPath,
            discoveredWorktrees: [discoveredAtNewPath]
        )

        #expect(reassociated)
        #expect(workspaceStore.pane(pane.id)?.residency == .backgrounded)
    }

    @Test("repoRemoved does not overwrite pendingUndo residency")
    func repoRemovedPreservesPendingUndoResidency() {
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            cacheStore: cacheStore
        )

        let repoPath = URL(fileURLWithPath: "/tmp/repo-remove-pending-undo")
        let repo = workspaceStore.addRepo(at: repoPath)
        let worktree = Worktree(
            name: "main",
            path: repoPath,
            branch: "main",
            isMainWorktree: true
        )
        workspaceStore.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        let worktreeId = workspaceStore.repos[0].worktrees[0].id

        let pane = workspaceStore.createPane(source: .worktree(worktreeId: worktreeId, repoId: repo.id))
        workspaceStore.setResidency(
            .pendingUndo(expiresAt: Date(timeIntervalSinceNow: 300)),
            for: pane.id
        )

        coordinator.handleTopology(
            SystemEnvelope.test(
                event: .topology(.repoRemoved(repoPath: repoPath))
            )
        )

        #expect(workspaceStore.pane(pane.id)?.residency.isPendingUndo == true)
    }
}
