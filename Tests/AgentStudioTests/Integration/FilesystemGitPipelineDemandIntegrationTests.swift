import AgentStudioGit
import Foundation
import Observation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct FilesystemGitPipelineDemandIntegrationTests {
    @Test("changed attention reuses fresh local remote and Forge facts")
    func changedAttentionReusesFreshRepositoryFacts() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let gitProvider = DemandIntegrationGitStatusProvider()
        let remoteReferenceProvider = DemandIntegrationRemoteReferenceProvider()
        let forgeProvider = DemandIntegrationForgeProvider()
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
        let rootPath = FileManager.default.temporaryDirectory
            .appending(path: "pipeline-demand-cache-\(UUIDv7.generate().uuidString)")
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
        let initialDemand = RepositoryFactDemandSnapshot(
            activePaneWorktreeId: worktreeId,
            sidebarAttendedWorktreeIds: [worktreeId],
            visibleActiveTabWorktreeIds: [],
            openWorktreeIds: [worktreeId],
            repositoryIdByWorktreeId: [worktreeId: repository.id]
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

        let sourceCallsBeforeAttentionChange = await sourceCallCounts(
            gitProvider: gitProvider,
            remoteReferenceProvider: remoteReferenceProvider,
            forgeProvider: forgeProvider
        )
        let cacheRevisionBeforeAttentionChange = repoCache.cacheRevision
        let worktreeInvalidationCounter = DemandIntegrationInvalidationCounter()
        let pullRequestInvalidationCounter = DemandIntegrationInvalidationCounter()
        let branchKey = try #require(RepoBranchKey(repoId: repository.id, branch: "main"))
        withObservationTracking {
            _ = repoCache.worktreeEnrichment(for: worktreeId)
        } onChange: {
            worktreeInvalidationCounter.record()
        }
        withObservationTracking {
            _ = repoCache.pullRequestFacts(for: branchKey)
        } onChange: {
            pullRequestInvalidationCounter.record()
        }
        let changedAttentionWithEqualMembership = RepositoryFactDemandSnapshot(
            activePaneWorktreeId: worktreeId,
            sidebarAttendedWorktreeIds: [],
            visibleActiveTabWorktreeIds: [worktreeId],
            openWorktreeIds: [worktreeId],
            repositoryIdByWorktreeId: [worktreeId: repository.id]
        )

        demandCoordinator.accept(changedAttentionWithEqualMembership)
        await demandCoordinator.waitUntilIdle()
        await pipeline.waitForRepositoryFactDemandAdmission()

        let sourceCallsAfterAttentionChange = await sourceCallCounts(
            gitProvider: gitProvider,
            remoteReferenceProvider: remoteReferenceProvider,
            forgeProvider: forgeProvider
        )
        #expect(sourceCallsAfterAttentionChange == sourceCallsBeforeAttentionChange)
        #expect(repoCache.cacheRevision == cacheRevisionBeforeAttentionChange)
        #expect(!worktreeInvalidationCounter.didFire)
        #expect(!pullRequestInvalidationCounter.didFire)
        #expect(repoCache.worktreeEnrichment(for: worktreeId)?.branch == "main")
        #expect(repoCache.pullRequestFactsForTest(worktreeId: worktreeId)?.openCount == 1)

        await shutdown(demandCoordinator: demandCoordinator, pipeline: pipeline, cacheCoordinator: cacheCoordinator)
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
    private(set) var statusCallCount = 0
    private(set) var lineDetailCallCount = 0
    private var lineDetailByRootPath: [URL: GitWorkingTreeLineDetail] = [:]

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
        let status = GitWorkingTreeStatus(
            summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
            branch: "main",
            origin: "git@github.com:askluna/agent-studio.git"
        )
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
    private(set) var callCount = 0

    func pullRequests(
        origin _: String,
        demandedBranches: Set<String>
    ) async -> ForgePullRequestQueryOutcome {
        callCount += 1
        guard demandedBranches == ["main"] else {
            return .failed(message: "unexpected demanded branch scope")
        }
        return .complete([
            ForgePullRequest(
                headRefName: "main",
                url: URL(string: "https://github.com/askluna/agent-studio/pull/1")!
            )
        ])
    }

    func currentCallCount() -> Int { callCount }
}

private final class DemandIntegrationSilentFSEventStreamClient: FSEventStreamClient, @unchecked Sendable {
    private let stream: AsyncStream<FSEventBatch>
    private let continuation: AsyncStream<FSEventBatch>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: FSEventBatch.self)
    }

    func events() -> AsyncStream<FSEventBatch> { stream }
    func consumeCoarseRefreshDebt() -> Set<UUID> { [] }
    func register(worktreeId _: UUID, repoId _: UUID, rootPath _: URL) {}
    func unregister(worktreeId _: UUID) {}
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
