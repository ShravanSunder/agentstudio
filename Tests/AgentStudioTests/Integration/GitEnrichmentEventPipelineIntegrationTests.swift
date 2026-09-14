import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct GitEnrichmentEventPipelineIntegrationTests {
    private func withEnrichmentHarness(
        gitProvider: some GitWorkingTreeStatusProvider,
        forgeProvider: some ForgeStatusProvider,
        _ body: @escaping @MainActor (GitEnrichmentPipelineHarness) async throws -> Void
    ) async rethrows {
        let harness = await GitEnrichmentPipelineHarness.make(
            gitProvider: gitProvider,
            forgeProvider: forgeProvider
        )
        await harness.start()
        do {
            try await body(harness)
            await harness.shutdown()
        } catch {
            await harness.shutdown()
            throw error
        }
    }

    @Test("worktree registration and filesChanged converge snapshot and branch enrichment")
    func worktreeRegistrationAndFilesChangedConvergeSnapshotAndBranchEnrichment() async {
        let rootPath = URL(fileURLWithPath: "/tmp/enrichment-\(UUID().uuidString)")

        await withEnrichmentHarness(
            gitProvider: StubGitWorkingTreeStatusProvider.stub { _ in
                GitWorkingTreeStatus(
                    summary: GitWorkingTreeSummary(changed: 2, staged: 1, untracked: 0),
                    branch: "feature/enrichment",
                    origin: "git@github.com:askluna/agent-studio.git"
                )
            },
            forgeProvider: StubForgeStatusProvider.stub { _ in
                .complete([
                    ForgePullRequest(
                        headRefName: "feature/enrichment",
                        url: URL(string: "https://github.com/askluna/agent-studio/pull/1")!
                    )
                ])
            }
        ) { harness in
            await waitForBusSubscriberCount(harness.bus, atLeast: 3)

            let repository = harness.workspaceStore.addRepo(at: rootPath)
            guard let worktreeId = repository.worktrees.first?.id else {
                Issue.record("canonical repository should include its primary worktree")
                return
            }
            let repoId = repository.id
            await harness.assertCanonicalProducerTopology()

            _ = await harness.bus.post(
                RuntimeEnvelopeHarness.topologyEnvelope(
                    event: .worktreeRegistered(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
                )
            )
            _ = await harness.bus.post(
                RuntimeEnvelopeHarness.filesystemEnvelope(
                    event: .filesChanged(
                        changeset: FileChangeset(
                            worktreeId: worktreeId,
                            repoId: repoId,
                            rootPath: rootPath,
                            paths: ["Sources/App.swift"],
                            timestamp: ContinuousClock().now,
                            batchSeq: 1
                        )
                    ),
                    repoId: repoId,
                    worktreeId: worktreeId
                )
            )

            await harness.advanceCacheApplyTick()
            await assertEventuallyMain("cache should converge snapshot + branch enrichment") {
                guard let enrichment = harness.repoCache.worktreeEnrichmentByWorktreeId[worktreeId] else {
                    return false
                }
                return enrichment.branch == "feature/enrichment"
                    && enrichment.snapshot?.summary.changed == 2
                    && enrichment.snapshot?.summary.staged == 1
            }
        }
    }

    @Test("forge counts stay isolated by repo even with the same branch name")
    func forgeCountsStayIsolatedByRepo() async {
        await withEnrichmentHarness(
            gitProvider: StubGitWorkingTreeStatusProvider.stub { _ in nil },
            forgeProvider: StubForgeStatusProvider.stub { origin in
                let count = origin.contains("repo-a") ? 1 : 2
                return .complete(
                    (0..<count).map { index in
                        ForgePullRequest(
                            headRefName: "main",
                            url: URL(string: "https://github.com/acme/repo/pull/\(index + 1)")!
                        )
                    }
                )
            }
        ) { harness in
            await waitForBusSubscriberCount(harness.bus, atLeast: 3)

            let repositoryA = harness.workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/repo-a"))
            let repositoryB = harness.workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/repo-b"))
            guard let worktreeA = repositoryA.worktrees.first?.id,
                let worktreeB = repositoryB.worktrees.first?.id
            else {
                Issue.record("canonical repositories should include their primary worktrees")
                return
            }
            let repoA = repositoryA.id
            let repoB = repositoryB.id
            let topologyAssertion = await harness.assertCanonicalProducerTopology()
            guard let lifetimeA = topologyAssertion.worktreeLifetimes[worktreeA],
                let lifetimeB = topologyAssertion.worktreeLifetimes[worktreeB]
            else {
                Issue.record("canonical worktrees should have observation lifetimes")
                return
            }

            await harness.forgeActor.register(
                worktreeId: worktreeA,
                repoId: repoA,
                rootPath: URL(fileURLWithPath: "/tmp/repo-a")
            )
            await harness.forgeActor.register(
                worktreeId: worktreeB,
                repoId: repoB,
                rootPath: URL(fileURLWithPath: "/tmp/repo-b")
            )
            await harness.forgeActor.setDemand(worktreeIds: [worktreeA, worktreeB])

            harness.repoCache.setWorktreeEnrichment(
                WorktreeEnrichment(worktreeId: worktreeA, repoId: repoA, branch: "main")
            )
            harness.repoCache.setWorktreeEnrichment(
                WorktreeEnrichment(worktreeId: worktreeB, repoId: repoB, branch: "main")
            )

            _ = await harness.bus.post(
                gitEnvelope(
                    event: .originChanged(repoId: repoA, from: "", to: "git@github.com:org/repo-a.git"),
                    repoId: repoA,
                    worktreeId: worktreeA,
                    observationLifetime: lifetimeA
                )
            )
            _ = await harness.bus.post(
                gitEnvelope(
                    event: .originChanged(repoId: repoB, from: "", to: "git@github.com:org/repo-b.git"),
                    repoId: repoB,
                    worktreeId: worktreeB,
                    observationLifetime: lifetimeB
                )
            )
            _ = await harness.bus.post(
                gitEnvelope(
                    event: .branchChanged(worktreeId: worktreeA, repoId: repoA, from: "seed", to: "main"),
                    repoId: repoA,
                    worktreeId: worktreeA,
                    observationLifetime: lifetimeA
                )
            )
            _ = await harness.bus.post(
                gitEnvelope(
                    event: .branchChanged(worktreeId: worktreeB, repoId: repoB, from: "seed", to: "main"),
                    repoId: repoB,
                    worktreeId: worktreeB,
                    observationLifetime: lifetimeB
                )
            )

            await harness.waitForStableForgeProjection(repoId: repoA)
            await harness.waitForStableForgeProjection(repoId: repoB)
            await harness.synchronizeCacheCoordinator(repoId: repoA, worktreeId: worktreeA)
            await harness.advanceCacheApplyTick()
            await assertEventuallyMain("forge counts should converge independently per repo") {
                harness.repoCache.pullRequestFactsForTest(worktreeId: worktreeA)?.openCount == 1
                    && harness.repoCache.pullRequestFactsForTest(worktreeId: worktreeB)?.openCount == 2
            }
        }
    }

    private func gitEnvelope(
        event: GitWorkingDirectoryEvent,
        repoId: UUID,
        worktreeId: UUID,
        observationLifetime: WorktreeObservationLifetime
    ) -> RuntimeEnvelope {
        .worktree(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(event),
                repoId: repoId,
                worktreeId: worktreeId,
                source: .system(.builtin(.gitWorkingDirectoryProjector)),
                observationLifetime: .worktree(observationLifetime)
            )
        )
    }
}
