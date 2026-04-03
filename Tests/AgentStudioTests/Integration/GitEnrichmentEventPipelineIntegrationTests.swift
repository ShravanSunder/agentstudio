import Foundation
import Testing

@testable import AgentStudio

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
    func worktreeRegistrationAndFilesChangedConvergeSnapshotAndBranchEnrichment() async throws {
        let repoId = UUID()
        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/enrichment-\(UUID().uuidString)")

        try await withEnrichmentHarness(
            gitProvider: StubGitWorkingTreeStatusProvider.stub { _ in
                GitWorkingTreeStatus(
                    summary: GitWorkingTreeSummary(changed: 2, staged: 1, untracked: 0),
                    branch: "feature/enrichment",
                    origin: "git@github.com:askluna/agent-studio.git"
                )
            },
            forgeProvider: StubForgeStatusProvider.stub { _, branches in
                Dictionary(uniqueKeysWithValues: branches.map { ($0, 1) })
            }
        ) { harness in
            await waitForBusSubscriberCount(harness.bus, atLeast: 3)

            _ = harness.workspaceStore.addRepo(at: rootPath)

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
    func forgeCountsStayIsolatedByRepo() async throws {
        let repoA = UUID()
        let repoB = UUID()
        let worktreeA = UUID()
        let worktreeB = UUID()

        try await withEnrichmentHarness(
            gitProvider: StubGitWorkingTreeStatusProvider.stub { _ in nil },
            forgeProvider: StubForgeStatusProvider.stub { origin, branches in
                var counts: [String: Int] = [:]
                for branch in branches {
                    counts[branch] = origin.contains("repo-a") ? 1 : 2
                }
                return counts
            }
        ) { harness in
            await waitForBusSubscriberCount(harness.bus, atLeast: 3)

            harness.repoCache.setWorktreeEnrichment(
                WorktreeEnrichment(worktreeId: worktreeA, repoId: repoA, branch: "main")
            )
            harness.repoCache.setWorktreeEnrichment(
                WorktreeEnrichment(worktreeId: worktreeB, repoId: repoB, branch: "main")
            )

            _ = await harness.bus.post(
                RuntimeEnvelopeHarness.gitEnvelope(
                    event: .originChanged(repoId: repoA, from: "", to: "git@github.com:org/repo-a.git"),
                    repoId: repoA,
                    worktreeId: worktreeA
                )
            )
            _ = await harness.bus.post(
                RuntimeEnvelopeHarness.gitEnvelope(
                    event: .originChanged(repoId: repoB, from: "", to: "git@github.com:org/repo-b.git"),
                    repoId: repoB,
                    worktreeId: worktreeB
                )
            )
            _ = await harness.bus.post(
                RuntimeEnvelopeHarness.gitEnvelope(
                    event: .branchChanged(worktreeId: worktreeA, repoId: repoA, from: "seed", to: "main"),
                    repoId: repoA,
                    worktreeId: worktreeA
                )
            )
            _ = await harness.bus.post(
                RuntimeEnvelopeHarness.gitEnvelope(
                    event: .branchChanged(worktreeId: worktreeB, repoId: repoB, from: "seed", to: "main"),
                    repoId: repoB,
                    worktreeId: worktreeB
                )
            )

            await assertEventuallyMain("forge counts should converge independently per repo") {
                harness.repoCache.pullRequestCountByWorktreeId[worktreeA] == 1
                    && harness.repoCache.pullRequestCountByWorktreeId[worktreeB] == 2
            }
        }
    }
}
