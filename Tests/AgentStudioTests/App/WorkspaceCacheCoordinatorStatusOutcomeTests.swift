import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@Suite(.serialized)
@MainActor
struct WorkspaceCacheCoordinatorStatusOutcomeTests {
    @Test
    func timeoutThresholdTransitionsMissingEnrichmentToUnavailable() {
        let workspaceStore = WorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        let repo = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/status-unavailable-missing-repo"))
        let worktree = Worktree(repoId: repo.id, name: "main", path: repo.repoPath, isMainWorktree: true)

        coordinator.handleEnrichment(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(
                    .statusOutcome(
                        worktreeId: worktree.id,
                        repoId: repo.id,
                        outcome: .timeout,
                        consecutiveTimeoutCount: AppPolicies.GitRefresh.statusUnavailableConsecutiveTimeoutThreshold
                    )
                ),
                repoId: repo.id,
                worktreeId: worktree.id,
                source: .system(.builtin(.gitWorkingDirectoryProjector))
            )
        )

        #expect(repoCache.repoEnrichment(for: repo.id) == .statusUnavailable(repoId: repo.id, reason: "timeout"))
    }

    @Test
    func repeatedStatusTimeoutBecomesUnavailableAndCompletedStatusClearsIt() {
        let workspaceStore = WorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        let repo = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/status-unavailable-repo"))
        repoCache.setRepoEnrichment(.awaitingOrigin(repoId: repo.id))
        let worktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: repo.repoPath,
            isMainWorktree: true
        )
        workspaceStore.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])

        for consecutiveTimeoutCount in 1...AppPolicies.GitRefresh.statusUnavailableConsecutiveTimeoutThreshold {
            coordinator.handleEnrichment(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .statusOutcome(
                            worktreeId: worktree.id,
                            repoId: repo.id,
                            outcome: .timeout,
                            consecutiveTimeoutCount: consecutiveTimeoutCount
                        )
                    ),
                    repoId: repo.id,
                    worktreeId: worktree.id,
                    source: .system(.builtin(.gitWorkingDirectoryProjector))
                )
            )
        }

        #expect(repoCache.repoEnrichment(for: repo.id) == .statusUnavailable(repoId: repo.id, reason: "timeout"))

        coordinator.handleEnrichment(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(
                    .statusOutcome(
                        worktreeId: worktree.id,
                        repoId: repo.id,
                        outcome: .completed,
                        consecutiveTimeoutCount: 0
                    )
                ),
                repoId: repo.id,
                worktreeId: worktree.id,
                source: .system(.builtin(.gitWorkingDirectoryProjector))
            )
        )

        #expect(repoCache.repoEnrichment(for: repo.id) == .awaitingOrigin(repoId: repo.id))
    }
}
