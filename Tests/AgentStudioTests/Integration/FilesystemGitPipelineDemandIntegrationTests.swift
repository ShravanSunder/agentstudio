import AgentStudioGit
import Foundation
import Observation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioRepoExplorer
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct FilesystemGitPipelineDemandIntegrationTests {
    @Test("unknown attended repository publishes its first complete sidebar baseline")
    func unknownAttendedRepositoryPublishesCompleteSidebarBaseline() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let expectedStatus = GitWorkingTreeStatus(
            summary: GitWorkingTreeSummary(
                changed: 2,
                staged: 1,
                untracked: 3,
                linesAdded: 69,
                linesDeleted: 19,
                aheadCount: 2,
                behindCount: 1,
                hasUpstream: true
            ),
            branch: "feature/sidebar-admission",
            origin: "git@github.com:askluna/agent-studio.git"
        )
        let gitProvider = DemandIntegrationGitStatusProvider(status: expectedStatus)
        let remoteReferenceProvider = DemandIntegrationRemoteReferenceProvider()
        let forgeProvider = DemandIntegrationForgeProvider(
            expectedBranch: "feature/sidebar-admission"
        )
        let pipeline = FilesystemGitPipeline(
            bus: bus,
            registrationDiscoveryProvider: DemandIntegrationRegistrationDiscoveryProvider(),
            gitWorkingTreeProvider: gitProvider,
            remoteReferenceRefreshProvider: remoteReferenceProvider,
            forgeStatusProvider: forgeProvider,
            fseventStreamClient: DemandIntegrationSilentFSEventStreamClient(),
            filesystemDebounceWindow: .zero,
            filesystemMaxFlushLatency: .zero,
            gitCoalescingWindow: .zero
        )
        let rootPath = demandIntegrationFixtureRootPath()
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootPath) }

        let workspaceStore = WorkspaceStore()
        let repository = workspaceStore.addRepo(at: rootPath)
        let worktree = try #require(repository.worktrees.first)
        let repoCache = RepoCacheAtom()
        let cacheCoordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        let demandCoordinator = RepositoryFactDemandCoordinator { snapshot in
            await pipeline.setRepositoryFactDemand(snapshot)
        }
        let activityTopology = try demandIntegrationActivityTopology(
            repository: repository,
            worktreeId: worktree.id
        )

        await cacheCoordinator.startConsuming()
        await pipeline.start()
        demandCoordinator.accept(
            RepositoryFactDemandInput(
                activePaneWorktreeId: nil,
                sidebarAttendedWorktreeIds: [worktree.id],
                visibleActiveTabWorktreeIds: [],
                openWorktreeIds: [],
                repositoryIdByWorktreeId: [worktree.id: repository.id],
                activityTopology: [activityTopology],
                localActivityHydrationDisposition: .unavailable,
                repositoryLocalActivityByStableKey: [:]
            )
        )
        await demandCoordinator.waitUntilIdle()
        await pipeline.register(
            worktreeId: worktree.id,
            repoId: repository.id,
            rootPath: rootPath
        )

        let baselinePublished = await eventually("unknown attended baseline should reach RepoCache") {
            repoCache.worktreeEnrichment(for: worktree.id)?.snapshot?.summary
                == expectedStatus.summary
        }
        #expect(baselinePublished)
        let enrichment = try #require(repoCache.worktreeEnrichment(for: worktree.id))
        #expect(enrichment.branch == "feature/sidebar-admission")
        #expect(await remoteReferenceProvider.currentStageFetchCallCount() == 0)
        #expect(await forgeProvider.currentCallCount() == 0)

        try expectCompleteSidebarBaseline(
            repoCache: repoCache,
            repository: repository,
            worktree: worktree
        )

        await shutdown(
            demandCoordinator: demandCoordinator,
            pipeline: pipeline,
            cacheCoordinator: cacheCoordinator
        )
    }

    @Test("changed attention reuses fresh local remote and Forge facts")
    func changedAttentionReusesFreshRepositoryFacts() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let gitProvider = DemandIntegrationGitStatusProvider()
        let remoteReferenceProvider = DemandIntegrationRemoteReferenceProvider()
        let forgeProvider = DemandIntegrationForgeProvider()
        let fseventStreamClient = DemandIntegrationSilentFSEventStreamClient()
        let pipeline = FilesystemGitPipeline(
            bus: bus,
            registrationDiscoveryProvider: DemandIntegrationRegistrationDiscoveryProvider(),
            gitWorkingTreeProvider: gitProvider,
            remoteReferenceRefreshProvider: remoteReferenceProvider,
            forgeStatusProvider: forgeProvider,
            fseventStreamClient: fseventStreamClient,
            filesystemDebounceWindow: .zero,
            filesystemMaxFlushLatency: .zero,
            gitCoalescingWindow: .zero
        )
        let rootPath = demandIntegrationFixtureRootPath()
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootPath) }

        let workspaceStore = WorkspaceStore()
        let repository = workspaceStore.addRepo(at: rootPath)
        let worktreeId = try #require(repository.worktrees.first?.id)
        let repoCache = RepoCacheAtom()
        let cacheCoordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        let demandCoordinator = RepositoryFactDemandCoordinator { snapshot in
            await pipeline.setRepositoryFactDemand(snapshot)
        }
        let activityTopology = try demandIntegrationActivityTopology(
            repository: repository,
            worktreeId: worktreeId
        )
        let initialDemand = RepositoryFactDemandInput(
            activePaneWorktreeId: worktreeId,
            sidebarAttendedWorktreeIds: [worktreeId],
            visibleActiveTabWorktreeIds: [],
            openWorktreeIds: [worktreeId],
            repositoryIdByWorktreeId: [worktreeId: repository.id],
            activityTopology: [activityTopology]
        )

        await cacheCoordinator.startConsuming()
        await pipeline.start()
        demandCoordinator.accept(initialDemand)
        await demandCoordinator.waitUntilIdle()
        await pipeline.register(worktreeId: worktreeId, repoId: repository.id, rootPath: rootPath)

        let allFactsArrived = await eventually("local, remote-reference, and Forge facts should settle") {
            let remoteFetchCallCount = await remoteReferenceProvider.currentStageFetchCallCount()
            let forgeCallCount = await forgeProvider.currentCallCount()
            return repoCache.worktreeEnrichment(for: worktreeId)?.branch == "main"
                && repoCache.pullRequestFactsForTest(worktreeId: worktreeId)?.openCount == 1
                && remoteFetchCallCount == 1
                && forgeCallCount == 1
        }
        #expect(allFactsArrived)

        await expectInitialSourceWorkSettled(
            gitProvider: gitProvider,
            remoteReferenceProvider: remoteReferenceProvider,
            forgeProvider: forgeProvider
        )

        let sourceCallsAfterAttentionChange = try await proveChangedAttentionReusesFacts(
            WarmAttentionProofContext(
                pipeline: pipeline,
                demandCoordinator: demandCoordinator,
                gitProvider: gitProvider,
                remoteReferenceProvider: remoteReferenceProvider,
                forgeProvider: forgeProvider,
                repoCache: repoCache,
                repositoryId: repository.id,
                worktreeId: worktreeId,
                activityTopology: activityTopology
            )
        )

        try await proveInactiveDemandAndColdMutation(
            ColdDemandProofContext(
                pipeline: pipeline,
                demandCoordinator: demandCoordinator,
                fseventStreamClient: fseventStreamClient,
                gitProvider: gitProvider,
                remoteReferenceProvider: remoteReferenceProvider,
                forgeProvider: forgeProvider,
                repoCache: repoCache,
                repositoryId: repository.id,
                worktreeId: worktreeId,
                activityTopology: activityTopology,
                sourceCallsBeforeInactivity: sourceCallsAfterAttentionChange
            )
        )

        await shutdown(demandCoordinator: demandCoordinator, pipeline: pipeline, cacheCoordinator: cacheCoordinator)
    }

    private func proveChangedAttentionReusesFacts(
        _ context: WarmAttentionProofContext
    ) async throws -> DemandIntegrationSourceCallCounts {
        let sourceCallsBeforeAttentionChange = await sourceCallCounts(
            gitProvider: context.gitProvider,
            remoteReferenceProvider: context.remoteReferenceProvider,
            forgeProvider: context.forgeProvider
        )
        let cacheRevisionBeforeAttentionChange = context.repoCache.cacheRevision
        let worktreeInvalidationCounter = DemandIntegrationInvalidationCounter()
        let pullRequestInvalidationCounter = DemandIntegrationInvalidationCounter()
        let branchKey = try #require(RepoBranchKey(repoId: context.repositoryId, branch: "main"))
        withObservationTracking {
            _ = context.repoCache.worktreeEnrichment(for: context.worktreeId)
        } onChange: {
            worktreeInvalidationCounter.record()
        }
        withObservationTracking {
            _ = context.repoCache.pullRequestFacts(for: branchKey)
        } onChange: {
            pullRequestInvalidationCounter.record()
        }
        context.demandCoordinator.accept(
            RepositoryFactDemandInput(
                activePaneWorktreeId: context.worktreeId,
                sidebarAttendedWorktreeIds: [],
                visibleActiveTabWorktreeIds: [context.worktreeId],
                openWorktreeIds: [context.worktreeId],
                repositoryIdByWorktreeId: [context.worktreeId: context.repositoryId],
                activityTopology: [context.activityTopology]
            )
        )
        await context.demandCoordinator.waitUntilIdle()
        await context.pipeline.waitForRepositoryFactDemandAdmission()

        let sourceCallsAfterAttentionChange = await sourceCallCounts(
            gitProvider: context.gitProvider,
            remoteReferenceProvider: context.remoteReferenceProvider,
            forgeProvider: context.forgeProvider
        )
        #expect(sourceCallsAfterAttentionChange == sourceCallsBeforeAttentionChange)
        #expect(context.repoCache.cacheRevision == cacheRevisionBeforeAttentionChange)
        #expect(!worktreeInvalidationCounter.didFire)
        #expect(!pullRequestInvalidationCounter.didFire)
        #expect(context.repoCache.worktreeEnrichment(for: context.worktreeId)?.branch == "main")
        #expect(context.repoCache.pullRequestFactsForTest(worktreeId: context.worktreeId)?.openCount == 1)
        return sourceCallsAfterAttentionChange
    }

    private func expectCompleteSidebarBaseline(
        repoCache: RepoCacheAtom,
        repository: Repo,
        worktree: Worktree
    ) throws {
        let presentationRepo = RepoPresentationItem(
            repo: repository,
            stableKey: repository.stableKey,
            worktreeStableKeysByID: [worktree.id: worktree.stableKey]
        )
        let projection = try RepoExplorerProjectionWorker.project(
            RepoExplorerProjectionRequest(
                generation: 1,
                snapshot: RepoExplorerSnapshot(
                    repos: [presentationRepo],
                    repoEnrichmentByRepoId: repoCache.repoEnrichmentByRepoId,
                    groupingMode: .repo,
                    query: ""
                ),
                collapsedGroupIds: [],
                isFiltering: false,
                trigger: .dataRefresh,
                worktreeEnrichmentSnapshot: repoCache.worktreeEnrichmentByWorktreeId,
                pullRequestFactsSnapshot: repoCache.pullRequestFactsByBranch,
                localActivityHydrationDisposition: .pending
            )
        )
        let worktreePresentations: [RepoExplorerMaterializedWorktreePresentation] =
            projection.materializationSnapshot.rows.compactMap { row in
                guard case .worktree(let presentation) = row.presentation else { return nil }
                return presentation
            }
        let worktreePresentation = try #require(worktreePresentations.first)
        #expect(worktreePresentation.branchName == "feature/sidebar-admission")
        #expect(worktreePresentation.branchStatus.isDirty)
        #expect(
            worktreePresentation.branchStatus.syncState
                == GitBranchStatus.SyncState.diverged(ahead: 2, behind: 1)
        )
        #expect(worktreePresentation.branchStatus.linesAdded == 69)
        #expect(worktreePresentation.branchStatus.linesDeleted == 19)
        #expect(worktreePresentation.branchStatus.untrackedFileCount == 3)
    }

    private func proveInactiveDemandAndColdMutation(_ context: ColdDemandProofContext) async throws {
        let referenceDate = Date()
        let inactiveActivity = try RepositoryLocalActivity(
            repositoryStableKey: context.activityTopology.repositoryStableKey,
            lastQualifyingActivityAt: nil,
            continuousCoverageStartedAt: referenceDate.addingTimeInterval(
                -AppPolicies.EntityRecency.applicationActivityHorizon - 1
            ),
            updatedAt: referenceDate,
            ownedPromotionAttemptID: nil,
            ownedPromotionStartedAt: nil,
            ownedPromotionUnsettled: false
        )
        let inactiveDemand = RepositoryFactDemandInput(
            activePaneWorktreeId: nil,
            sidebarAttendedWorktreeIds: [context.worktreeId],
            visibleActiveTabWorktreeIds: [],
            openWorktreeIds: [],
            repositoryIdByWorktreeId: [context.worktreeId: context.repositoryId],
            activityTopology: [context.activityTopology],
            localActivityHydrationDisposition: .authoritative,
            repositoryLocalActivityByStableKey: [
                inactiveActivity.repositoryStableKey: inactiveActivity
            ]
        )
        context.demandCoordinator.accept(inactiveDemand)
        await context.demandCoordinator.waitUntilIdle()
        await context.pipeline.waitForRepositoryFactDemandAdmission()

        let sourceCallsAfterInactivity = await sourceCallCounts(
            gitProvider: context.gitProvider,
            remoteReferenceProvider: context.remoteReferenceProvider,
            forgeProvider: context.forgeProvider
        )
        #expect(sourceCallsAfterInactivity == context.sourceCallsBeforeInactivity)
        #expect(context.repoCache.worktreeEnrichment(for: context.worktreeId)?.branch == "main")
        #expect(context.repoCache.pullRequestFactsForTest(worktreeId: context.worktreeId)?.openCount == 1)
        #expect(await context.pipeline.gitLogicalDebtSnapshot().futureAutomaticCount == 0)

        context.fseventStreamClient.send(
            FSEventBatch(worktreeId: context.worktreeId, paths: ["Sources/ColdMutation.swift"])
        )
        let coldMutationSettled = await eventually("cold mutation should run local Git only") {
            let sourceCalls = await sourceCallCounts(
                gitProvider: context.gitProvider,
                remoteReferenceProvider: context.remoteReferenceProvider,
                forgeProvider: context.forgeProvider
            )
            return sourceCalls.gitStatus == sourceCallsAfterInactivity.gitStatus + 1
                && sourceCalls.remoteFetch == sourceCallsAfterInactivity.remoteFetch
                && sourceCalls.forge == sourceCallsAfterInactivity.forge
        }
        #expect(coldMutationSettled)
        #expect(await context.pipeline.gitLogicalDebtSnapshot().futureAutomaticCount == 0)
    }

    private func eventually(
        _ description: String,
        maxTurns: Int = 50_000,
        condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        for _ in 0..<maxTurns {
            if await condition() {
                return true
            }
            await Task.yield()
        }
        Issue.record("\(description) timed out")
        return false
    }

    private func sourceCallCounts(
        gitProvider: DemandIntegrationGitStatusProvider,
        remoteReferenceProvider: DemandIntegrationRemoteReferenceProvider,
        forgeProvider: DemandIntegrationForgeProvider
    ) async -> DemandIntegrationSourceCallCounts {
        let gitStatus = await gitProvider.currentStatusCallCount()
        let gitLineDetail = await gitProvider.currentLineDetailCallCount()
        let remote = await remoteReferenceProvider.currentCallCounts()
        let forge = await forgeProvider.currentCallCount()
        return DemandIntegrationSourceCallCounts(
            gitStatus: gitStatus,
            gitLineDetail: gitLineDetail,
            remoteCapture: remote.capture,
            remoteFetch: remote.fetch,
            remotePromote: remote.promote,
            remoteCleanup: remote.cleanup,
            forge: forge
        )
    }

    private func expectInitialSourceWorkSettled(
        gitProvider: DemandIntegrationGitStatusProvider,
        remoteReferenceProvider: DemandIntegrationRemoteReferenceProvider,
        forgeProvider: DemandIntegrationForgeProvider
    ) async {
        let expectedCounts = DemandIntegrationSourceCallCounts(
            gitStatus: 2,
            gitLineDetail: 1,
            remoteCapture: 2,
            remoteFetch: 1,
            remotePromote: 1,
            remoteCleanup: 1,
            forge: 1
        )
        let settled = await eventually("initial source work should settle completely") {
            await sourceCallCounts(
                gitProvider: gitProvider,
                remoteReferenceProvider: remoteReferenceProvider,
                forgeProvider: forgeProvider
            ) == expectedCounts
        }
        let actualCounts = await sourceCallCounts(
            gitProvider: gitProvider,
            remoteReferenceProvider: remoteReferenceProvider,
            forgeProvider: forgeProvider
        )
        #expect(settled, Comment(rawValue: "initial source call counts: \(actualCounts)"))
    }

    private func shutdown(
        demandCoordinator: RepositoryFactDemandCoordinator,
        pipeline: FilesystemGitPipeline,
        cacheCoordinator: WorkspaceCacheCoordinator
    ) async {
        await demandCoordinator.shutdown()
        await pipeline.shutdown()
        await cacheCoordinator.shutdown()
    }
}

private struct ColdDemandProofContext {
    let pipeline: FilesystemGitPipeline
    let demandCoordinator: RepositoryFactDemandCoordinator
    let fseventStreamClient: DemandIntegrationSilentFSEventStreamClient
    let gitProvider: DemandIntegrationGitStatusProvider
    let remoteReferenceProvider: DemandIntegrationRemoteReferenceProvider
    let forgeProvider: DemandIntegrationForgeProvider
    let repoCache: RepoCacheAtom
    let repositoryId: UUID
    let worktreeId: UUID
    let activityTopology: RepositoryActivityTopology
    let sourceCallsBeforeInactivity: DemandIntegrationSourceCallCounts
}

private struct WarmAttentionProofContext {
    let pipeline: FilesystemGitPipeline
    let demandCoordinator: RepositoryFactDemandCoordinator
    let gitProvider: DemandIntegrationGitStatusProvider
    let remoteReferenceProvider: DemandIntegrationRemoteReferenceProvider
    let forgeProvider: DemandIntegrationForgeProvider
    let repoCache: RepoCacheAtom
    let repositoryId: UUID
    let worktreeId: UUID
    let activityTopology: RepositoryActivityTopology
}

private func demandIntegrationFixtureRootPath() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "pipeline-demand-cache-\(UUIDv7.generate().uuidString)")
}

private func demandIntegrationActivityTopology(
    repository: Repo,
    worktreeId: UUID
) throws -> RepositoryActivityTopology {
    RepositoryActivityTopology(
        repositoryID: repository.id,
        repositoryStableKey: repository.stableKey,
        worktreeStableKeysByID: [worktreeId: try #require(repository.worktrees.first?.stableKey)]
    )
}

private final class DemandIntegrationInvalidationCounter: @unchecked Sendable {
    private(set) var didFire = false

    func record() {
        didFire = true
    }
}

private struct DemandIntegrationSourceCallCounts: Equatable {
    let gitStatus: Int
    let gitLineDetail: Int
    let remoteCapture: Int
    let remoteFetch: Int
    let remotePromote: Int
    let remoteCleanup: Int
    let forge: Int
}

private struct DemandIntegrationRemoteCallCounts: Equatable {
    let capture: Int
    let fetch: Int
    let promote: Int
    let cleanup: Int
}

private actor DemandIntegrationGitStatusProvider: GitWorkingTreeStatusProvider {
    private let status: GitWorkingTreeStatus
    private(set) var statusCallCount = 0
    private(set) var lineDetailCallCount = 0
    private var lineDetailByRootPath: [URL: GitWorkingTreeLineDetail] = [:]

    init(
        status: GitWorkingTreeStatus = GitWorkingTreeStatus(
            summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
            branch: "main",
            origin: "git@github.com:askluna/agent-studio.git"
        )
    ) {
        self.status = status
    }

    func statusResult(
        for rootPath: URL,
        pathspecs _: [String]?
    ) async -> GitWorkingTreeStatusResult {
        .available(recordStatus(for: rootPath))
    }

    func statusFactsResult(
        for rootPath: URL,
        pathspecs _: [String]?
    ) async -> GitWorkingTreeStatusFactsResult {
        .available(GitWorkingTreeStatusFacts(status: recordStatus(for: rootPath)))
    }

    func lineDetailResult(for rootPath: URL) async -> GitWorkingTreeLineDetailResult {
        lineDetailCallCount += 1
        guard let detail = lineDetailByRootPath[rootPath.standardizedFileURL] else {
            return .unavailable(GitWorkingTreeStatusUnavailable(reason: .providerReturnedNil))
        }
        return .available(detail)
    }

    func currentStatusCallCount() -> Int { statusCallCount }
    func currentLineDetailCallCount() -> Int { lineDetailCallCount }

    private func recordStatus(for rootPath: URL) -> GitWorkingTreeStatus {
        statusCallCount += 1
        lineDetailByRootPath[rootPath.standardizedFileURL] = GitWorkingTreeLineDetail(status: status)
        return status
    }
}

private actor DemandIntegrationRemoteReferenceProvider: RemoteReferenceRefreshProviding {
    private let origin = "git@github.com:askluna/agent-studio.git"
    private(set) var captureCallCount = 0
    private(set) var stageFetchCallCount = 0
    private(set) var promoteCallCount = 0
    private(set) var cleanupCallCount = 0

    func captureRemoteTrackingSnapshot(
        repositoryPath: URL,
        remoteName: String
    ) async throws -> GitRemoteTrackingSnapshot {
        captureCallCount += 1
        return GitRemoteTrackingSnapshot(
            repositoryPath: repositoryPath,
            repositoryCommonDirectory: repositoryPath.appending(path: ".git"),
            remoteName: remoteName,
            configuredRemoteURL: origin,
            effectiveFetchURL: origin,
            references: []
        )
    }

    func stageFetch(
        snapshot: GitRemoteTrackingSnapshot,
        stagingId: UUID
    ) async throws -> GitStagedFetchResult {
        stageFetchCallCount += 1
        return GitStagedFetchResult(
            snapshot: snapshot,
            handle: GitStagedFetchHandle(
                repositoryCommonDirectory: snapshot.repositoryCommonDirectory,
                stagingID: stagingId
            ),
            promotionGuard: nil,
            updates: [],
            verifications: [],
            deletions: []
        )
    }

    func promoteStagedFetch(_: GitStagedFetchResult) async throws {
        promoteCallCount += 1
    }

    func cleanupStagedFetch(_: GitStagedFetchHandle) async throws {
        cleanupCallCount += 1
    }

    func cleanupAbandonedStagedFetches(
        repositoryCommonDirectory _: URL,
        retainedStagingIds _: Set<UUID>
    ) async throws {}

    func currentStageFetchCallCount() -> Int { stageFetchCallCount }

    func currentCallCounts() -> DemandIntegrationRemoteCallCounts {
        DemandIntegrationRemoteCallCounts(
            capture: captureCallCount,
            fetch: stageFetchCallCount,
            promote: promoteCallCount,
            cleanup: cleanupCallCount
        )
    }
}

private actor DemandIntegrationForgeProvider: ForgeStatusProvider {
    private let expectedBranch: String
    private(set) var callCount = 0

    init(expectedBranch: String = "main") {
        self.expectedBranch = expectedBranch
    }

    func pullRequests(
        origin _: String,
        demandedBranches: Set<String>
    ) async -> ForgePullRequestQueryOutcome {
        callCount += 1
        guard demandedBranches == [expectedBranch] else {
            return .failed(message: "unexpected demanded branch scope")
        }
        return .complete([
            ForgePullRequest(
                headRefName: expectedBranch,
                url: URL(string: "https://github.com/askluna/agent-studio/pull/1")!
            )
        ])
    }

    func currentCallCount() -> Int { callCount }
}

private final class DemandIntegrationSilentFSEventStreamClient: FSEventStreamClient, @unchecked Sendable {
    private let stream: AsyncStream<FSEventIngressItem>
    private let continuation: AsyncStream<FSEventIngressItem>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: FSEventIngressItem.self)
    }

    func events() -> AsyncStream<FSEventIngressItem> { stream }
    func consumeOverflowRecoveries() -> [FSEventOverflowRecovery] { [] }
    func register(worktreeId _: UUID, repoId _: UUID, rootPath _: URL) {}
    func unregister(worktreeId _: UUID) {}
    func send(_ batch: FSEventBatch) { continuation.yield(.batch(batch)) }
    func shutdown() { continuation.finish() }
}

private struct DemandIntegrationRegistrationDiscoveryProvider: RepoScanner.GitRepositoryDiscoveryProvider {
    func discoveryOutcome(for url: URL) -> GitRepositoryDiscoveryOutcome {
        .validated(
            RepoScanner.ResolvedGitEntry(
                path: url,
                kind: .cloneRoot,
                repositoryKey: "test:\(url.path)"
            )
        )
    }
}
