import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite("Workspace cache apply governor", .serialized)
struct WorkspaceCacheCoordinatorApplyGovernorTests {
    @Test("repository projections coalesce by repository and apply latest sequence atomically")
    func repositoryProjectionsCoalesceAndApplyAtomically() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = WorkspaceStore()
        let repoCache = RepoCacheAtom()
        let clock = TestPushClock()
        let repo = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/apply-governor-projection-repo"))
        let repoId = repo.id
        let observationLifetime = try #require(
            workspaceStore.repositoryTopologyAtom.repositoryObservationLifetimes[repoId]
        )
        let branch = "feature/coalesced"
        let branchKey = RepoBranchKey(repoId: repoId, branch: branch)!
        let facts = PullRequestFacts(openCount: 1, exactOpenURL: nil)
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in },
            enrichmentApplyTickCadence: .milliseconds(25),
            enrichmentApplyClock: clock
        )
        await coordinator.startConsuming()

        await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .forge(
                        .pullRequestRepositoryProjectionChanged(
                            repoId: repoId,
                            projection: .loading(
                                baseline: .unknown,
                                requestIdentity: 1
                            ),
                            invalidatedBranches: []
                        )
                    ),
                    repoId: repoId,
                    worktreeId: nil,
                    source: .system(.service(.gitForge(provider: "github"))),
                    seq: 1,
                    observationLifetime: .repository(observationLifetime)
                )
            )
        )
        await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .forge(
                        .pullRequestRepositoryProjectionChanged(
                            repoId: repoId,
                            projection: .stable(
                                .ready(confirmedFactsByBranch: [branch: facts])
                            ),
                            invalidatedBranches: []
                        )
                    ),
                    repoId: repoId,
                    worktreeId: nil,
                    source: .system(.service(.gitForge(provider: "github"))),
                    seq: 2,
                    observationLifetime: .repository(observationLifetime)
                )
            )
        )
        await eventually("both repository projections should coalesce before draining") {
            clock.pendingSleepCount == 1
                && coordinator.pendingRepositoryProjectionSupersessionCount == 1
        }
        #expect(repoCache.cacheRevision == 0)

        clock.advance(by: .milliseconds(25))
        await eventually("latest repository projection should apply") {
            repoCache.pullRequestFacts(for: branchKey) == facts
        }
        await coordinator.shutdown()

        #expect(repoCache.cacheRevision == 1)
        #expect(!repoCache.isPullRequestLoading(forRepository: repoId))
        #expect(repoCache.pullRequestFacts(for: branchKey) == facts)
    }

    @Test("rapid enrichment facts coalesce to one apply per worktree in one drain turn")
    func rapidEnrichmentFactsCoalesceByWorktree() async throws {
        let traceDirectory = FileManager.default.temporaryDirectory.appending(
            path: "apply-governor-trace-\(UUIDv7.generate().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: traceDirectory) }
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "workspace-cache-apply-governor",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 937,
            timeUnixNano: { 937 }
        )
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: traceRuntime)
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = WorkspaceStore()
        let repoCache = RepoCacheAtom()
        let clock = TestPushClock()
        let fixture = try makeThreeWorktreeFixture(in: workspaceStore)
        let repo = fixture.repository
        let registeredWorktrees = fixture.worktrees
        let worktreeIds = registeredWorktrees.map(\.id)
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in },
            enrichmentApplyTickCadence: .milliseconds(25),
            enrichmentApplyClock: clock,
            performanceTraceRecorder: recorder
        )
        await coordinator.startConsuming()

        for sequence in 0..<12 {
            let worktree = registeredWorktrees[sequence % registeredWorktrees.count]
            let worktreeLifetime = try #require(fixture.worktreeLifetimes[worktree.id])
            await bus.post(
                .worktree(
                    WorktreeEnvelope.test(
                        event: .gitWorkingDirectory(
                            .snapshotChanged(
                                snapshot: GitWorkingTreeSnapshot(
                                    worktreeId: worktree.id,
                                    repoId: repo.id,
                                    rootPath: worktree.path,
                                    summary: GitWorkingTreeSummary(
                                        changed: sequence,
                                        staged: 0,
                                        untracked: 0
                                    ),
                                    branch: "branch-\(sequence)"
                                )
                            )
                        ),
                        repoId: repo.id,
                        worktreeId: worktree.id,
                        source: .system(.builtin(.gitWorkingDirectoryProjector)),
                        seq: UInt64(sequence),
                        observationLifetime: .worktree(worktreeLifetime)
                    )
                )
            )
        }
        await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .originChanged(
                            repoId: repo.id,
                            from: "",
                            to: "git@github.com:askluna/agent-studio.git"
                        )
                    ),
                    repoId: repo.id,
                    worktreeId: registeredWorktrees[0].id,
                    source: .system(.builtin(.gitWorkingDirectoryProjector)),
                    observationLifetime: .worktree(
                        try #require(fixture.worktreeLifetimes[registeredWorktrees[0].id]))
                )
            )
        )
        await eventually("ordering flush after enrichment burst") {
            repoCache.repoEnrichmentByRepoId[repo.id] != nil
        }
        #expect(repoCache.repoEnrichmentByRepoId[repo.id] != nil)

        await coordinator.shutdown()
        try await recorder.drain()

        #expect(repoCache.worktreeEnrichmentByWorktreeId.count == worktreeIds.count)
        let outputFileURL = try #require(traceRuntime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"performance.apply_governor.drain\""))
        #expect(contents.contains("\"agentstudio.performance.apply_governor.batch.count\":3"))
        #expect(contents.contains("\"agentstudio.performance.apply_governor.superseded.count\":9"))
        #expect(contents.contains("\"agentstudio.performance.apply_governor.carried_over.count\":0"))
        #expect(contents.contains("\"agentstudio.performance.apply_governor.awaited_ms\":"))
        #expect(contents.contains("\"agentstudio.performance.apply_governor.mainactor_held_ms\":"))
        #expect(contents.contains("\"agentstudio.performance.apply_governor.max_single_fact_ms\":"))
    }

    @Test
    func branchChangedAfterCachedSnapshotPreservesSnapshot() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = WorkspaceStore()
        let repoCache = RepoCacheAtom()
        let clock = TestPushClock()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in },
            enrichmentApplyTickCadence: .milliseconds(25),
            enrichmentApplyClock: clock
        )
        let repo = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/apply-governor-branch-repo"))
        let worktree = try #require(repo.worktrees.first { $0.isMainWorktree })
        let repoId = repo.id
        let worktreeId = worktree.id
        let observationLifetime = try #require(
            workspaceStore.repositoryTopologyAtom.worktreeObservationLifetimes[worktreeId]
        )
        let snapshot = GitWorkingTreeSnapshot(
            worktreeId: worktreeId,
            repoId: repoId,
            rootPath: worktree.path,
            summary: GitWorkingTreeSummary(changed: 2, staged: 1, untracked: 3),
            branch: "main"
        )

        await coordinator.startConsuming()
        await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(.snapshotChanged(snapshot: snapshot)),
                    repoId: repoId,
                    worktreeId: worktreeId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector)),
                    observationLifetime: .worktree(observationLifetime)
                )))
        await eventually("snapshot flush should be scheduled") {
            clock.pendingSleepCount == 1
        }
        #expect(clock.pendingSleepCount == 1)
        clock.advance(by: .milliseconds(25))
        await eventually("snapshot should apply before branch update") {
            repoCache.worktreeEnrichment(for: worktreeId)?.snapshot == snapshot
        }
        #expect(repoCache.worktreeEnrichment(for: worktreeId)?.snapshot == snapshot)

        await bus.post(
            .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .branchChanged(
                            worktreeId: worktreeId,
                            repoId: repoId,
                            from: "main",
                            to: "feature/new"
                        )
                    ),
                    repoId: repoId,
                    worktreeId: worktreeId,
                    source: .system(.builtin(.gitWorkingDirectoryProjector)),
                    observationLifetime: .worktree(observationLifetime)
                )))
        await eventually("branch flush should be scheduled") {
            clock.pendingSleepCount == 1
        }
        #expect(clock.pendingSleepCount == 1)
        clock.advance(by: .milliseconds(25))
        await eventually("branch update should preserve cached snapshot") {
            repoCache.worktreeEnrichment(for: worktreeId)?.branch == "feature/new"
        }

        await coordinator.shutdown()

        #expect(repoCache.worktreeEnrichment(for: worktreeId)?.branch == "feature/new")
        #expect(repoCache.worktreeEnrichment(for: worktreeId)?.snapshot == snapshot)
    }

    private func makeThreeWorktreeFixture(in workspaceStore: WorkspaceStore) throws -> ThreeWorktreeFixture {
        let repository = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/apply-governor-repo"))
        let mainWorktree = try #require(repository.worktrees.first { $0.isMainWorktree })
        let linkedWorktrees = (0..<2).map { index in
            Worktree(
                repoId: repository.id,
                name: "linked-\(index)",
                path: URL(fileURLWithPath: "/tmp/apply-governor-linked-\(index)")
            )
        }
        workspaceStore.reconcileDiscoveredWorktrees(
            repository.id,
            worktrees: [mainWorktree] + linkedWorktrees
        )

        let registeredRepository = try #require(
            workspaceStore.repositoryTopologyAtom.repo(repository.id)
        )
        let registeredWorktrees = try #require(
            registeredRepository.worktrees.count == 3 ? registeredRepository.worktrees : nil
        )
        return ThreeWorktreeFixture(
            repository: registeredRepository,
            worktrees: registeredWorktrees,
            worktreeLifetimes: workspaceStore.repositoryTopologyAtom.worktreeObservationLifetimes
        )
    }

    private struct ThreeWorktreeFixture {
        let repository: Repo
        let worktrees: [Worktree]
        let worktreeLifetimes: [UUID: WorktreeObservationLifetime]
    }
}
