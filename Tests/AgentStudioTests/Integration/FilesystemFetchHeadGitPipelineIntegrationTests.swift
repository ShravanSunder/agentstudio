import AgentStudioGit
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@MainActor
@Suite(.serialized)
struct FilesystemFetchHeadGitPipelineIntegrationTests {
    @Test("FETCH_HEAD bookkeeping does not cross the local status provider boundary")
    func fetchHeadBookkeepingDoesNotInvokeLocalStatusProvider() async throws {
        let provider = FetchHeadStatusProvider()
        let pipeline = FilesystemGitPipeline(
            bus: EventBus<RuntimeEnvelope>(),
            registrationDiscoveryProvider: FetchHeadRegistrationDiscoveryProvider(),
            gitWorkingTreeProvider: provider,
            remoteReferenceRefreshProvider: FetchHeadRemoteReferenceProvider(),
            fseventStreamClient: FetchHeadSilentFSEventStreamClient(),
            filesystemDebounceWindow: .zero,
            filesystemMaxFlushLatency: .zero,
            gitCoalescingWindow: .zero
        )
        await pipeline.start()

        let rootPath = FileManager.default.temporaryDirectory
            .appending(path: "pipeline-fetch-head-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootPath) }

        let worktreeId = UUIDv7.generate()
        let repoId = UUIDv7.generate()
        await pipeline.setRepositoryFactDemand(
            RepositoryFactDemandSnapshot(
                activePaneWorktreeId: worktreeId,
                sidebarAttendedWorktreeIds: [],
                visibleActiveTabWorktreeIds: [],
                openWorktreeIds: [],
                repositoryIdByWorktreeId: [worktreeId: repoId],
                warmRepositoryIds: [repoId],
                locallyInactiveRepositoryIds: [],
                warmAutomaticWorktreeIds: [worktreeId],
                locallyInactiveWorktreeIds: []
            )
        )
        await pipeline.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
        let initialReadCompleted = await eventually("registration status should settle") {
            await provider.callCount >= 1
        }
        #expect(initialReadCompleted)
        await provider.resetRecordedRequests()

        await pipeline.enqueueRawPathsForTesting(
            worktreeId: worktreeId,
            paths: [".git/FETCH_HEAD", ".git/FETCH_HEAD.lock"]
        )
        for _ in 0..<300 {
            await Task.yield()
        }
        #expect(await provider.callCount == 0)

        await pipeline.enqueueRawPathsForTesting(
            worktreeId: worktreeId,
            paths: [".git/index"]
        )
        let indexReadCompleted = await eventually("index mutation should run local status") {
            await provider.callCount == 1
        }
        #expect(indexReadCompleted)

        await pipeline.shutdown()
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
}

private actor FetchHeadStatusProvider: GitWorkingTreeStatusProvider {
    private(set) var callCount = 0

    func resetRecordedRequests() {
        callCount = 0
    }

    func statusResult(for rootPath: URL, pathspecs _: [String]?) async -> GitWorkingTreeStatusResult {
        .available(recordStatusRead())
    }

    func statusFactsResult(
        for rootPath: URL,
        pathspecs _: [String]?
    ) async -> GitWorkingTreeStatusFactsResult {
        .available(GitWorkingTreeStatusFacts(status: recordStatusRead()))
    }

    func lineDetailResult(for rootPath: URL) async -> GitWorkingTreeLineDetailResult {
        .available(GitWorkingTreeLineDetail(status: makeStatus()))
    }

    private func recordStatusRead() -> GitWorkingTreeStatus {
        callCount += 1
        return makeStatus()
    }

    private func makeStatus() -> GitWorkingTreeStatus {
        GitWorkingTreeStatus(
            summary: GitWorkingTreeSummary(
                changed: 0,
                staged: 0,
                untracked: 0,
                linesAdded: 0,
                linesDeleted: 0,
                aheadCount: 0,
                behindCount: 0,
                hasUpstream: true
            ),
            branch: "main",
            origin: "git@github.com:askluna/agent-studio.git"
        )
    }
}

private final class FetchHeadSilentFSEventStreamClient: FSEventStreamClient, @unchecked Sendable {
    private let stream: AsyncStream<FSEventIngressItem>
    private let continuation: AsyncStream<FSEventIngressItem>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: FSEventIngressItem.self)
    }

    func events() -> AsyncStream<FSEventIngressItem> { stream }
    func consumeOverflowRecoveries() -> [FSEventOverflowRecovery] { [] }
    func register(worktreeId _: UUID, repoId _: UUID, rootPath _: URL) {}
    func unregister(worktreeId _: UUID) {}
    func shutdown() { continuation.finish() }
}

private struct FetchHeadRegistrationDiscoveryProvider: RepoScanner.GitRepositoryDiscoveryProvider {
    func discoveryOutcome(for url: URL) async -> GitRepositoryDiscoveryOutcome {
        .validated(
            RepoScanner.ResolvedGitEntry(
                path: url,
                kind: .cloneRoot,
                repositoryKey: "test:\(url.path)"
            )
        )
    }
}

private struct FetchHeadRemoteReferenceProvider: RemoteReferenceRefreshProviding {
    private let origin = "git@github.com:askluna/agent-studio.git"

    func captureRemoteTrackingSnapshot(
        repositoryPath: URL,
        remoteName: String
    ) async throws -> GitRemoteTrackingSnapshot {
        GitRemoteTrackingSnapshot(
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
        GitStagedFetchResult(
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

    func promoteStagedFetch(_: GitStagedFetchResult) async throws {}
    func cleanupStagedFetch(_: GitStagedFetchHandle) async throws {}

    func cleanupAbandonedStagedFetches(
        repositoryCommonDirectory _: URL,
        retainedStagingIds _: Set<UUID>
    ) async throws {}
}
