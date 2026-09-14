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
    func timeoutThresholdTransitionsMissingEnrichmentToUnavailable() throws {
        let workspaceStore = WorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        let repo = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/status-unavailable-missing-repo"))
        let worktree = try #require(repo.worktrees.first { $0.isMainWorktree })
        let observationLifetime = try #require(
            workspaceStore.repositoryTopologyAtom.worktreeObservationLifetimes[worktree.id]
        )

        coordinator.handleEnrichment(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(
                    .statusOutcome(
                        GitStatusOutcomeFact(
                            worktreeId: worktree.id,
                            repoId: repo.id,
                            outcome: .timeout,
                            reason: .timeout,
                            consecutiveFailureCount: AppPolicies.GitRefresh.statusUnavailableConsecutiveFailureThreshold
                        ))
                ),
                repoId: repo.id,
                worktreeId: worktree.id,
                source: .system(.builtin(.gitWorkingDirectoryProjector)),
                observationLifetime: .worktree(observationLifetime)
            )
        )

        #expect(repoCache.repoEnrichment(for: repo.id) == .statusUnavailable(repoId: repo.id, reason: "timeout"))
    }

    @Test
    func repeatedStatusTimeoutBecomesUnavailableAndCompletedStatusClearsIt() throws {
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
        let worktree = try #require(repo.worktrees.first { $0.isMainWorktree })
        let observationLifetime = try #require(
            workspaceStore.repositoryTopologyAtom.worktreeObservationLifetimes[worktree.id]
        )

        for consecutiveFailureCount in 1...AppPolicies.GitRefresh.statusUnavailableConsecutiveFailureThreshold {
            coordinator.handleEnrichment(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .statusOutcome(
                            GitStatusOutcomeFact(
                                worktreeId: worktree.id,
                                repoId: repo.id,
                                outcome: .timeout,
                                reason: .timeout,
                                consecutiveFailureCount: consecutiveFailureCount
                            ))
                    ),
                    repoId: repo.id,
                    worktreeId: worktree.id,
                    source: .system(.builtin(.gitWorkingDirectoryProjector)),
                    observationLifetime: .worktree(observationLifetime)
                )
            )
        }

        #expect(repoCache.repoEnrichment(for: repo.id) == .statusUnavailable(repoId: repo.id, reason: "timeout"))

        coordinator.handleEnrichment(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(
                    .statusOutcome(
                        GitStatusOutcomeFact(
                            worktreeId: worktree.id,
                            repoId: repo.id,
                            outcome: .completed,
                            reason: nil,
                            consecutiveFailureCount: 0
                        ))
                ),
                repoId: repo.id,
                worktreeId: worktree.id,
                source: .system(.builtin(.gitWorkingDirectoryProjector)),
                observationLifetime: .worktree(observationLifetime)
            )
        )

        #expect(repoCache.repoEnrichment(for: repo.id) == .awaitingOrigin(repoId: repo.id))
    }

    @Test
    func repeatedSDKErrorBecomesUnavailableWithTypedReason() throws {
        let workspaceStore = WorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        let repo = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/status-unavailable-sdk-error"))
        repoCache.setRepoEnrichment(.awaitingOrigin(repoId: repo.id))
        let worktree = try #require(repo.worktrees.first { $0.isMainWorktree })
        let observationLifetime = try #require(
            workspaceStore.repositoryTopologyAtom.worktreeObservationLifetimes[worktree.id]
        )

        for consecutiveFailureCount in 1...AppPolicies.GitRefresh.statusUnavailableConsecutiveFailureThreshold {
            coordinator.handleEnrichment(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .statusOutcome(
                            GitStatusOutcomeFact(
                                worktreeId: worktree.id,
                                repoId: repo.id,
                                outcome: .unavailable,
                                reason: .sdkError,
                                consecutiveFailureCount: consecutiveFailureCount
                            ))
                    ),
                    repoId: repo.id,
                    worktreeId: worktree.id,
                    source: .system(.builtin(.gitWorkingDirectoryProjector)),
                    observationLifetime: .worktree(observationLifetime)
                )
            )
        }

        #expect(repoCache.repoEnrichment(for: repo.id) == .statusUnavailable(repoId: repo.id, reason: "sdk_error"))
    }
}
