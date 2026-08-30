import AgentStudioGit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite("FilesystemGitPipeline remote references", .serialized)
struct FilesystemGitRemoteReferenceTests {
    @Test("complete repository demand reaches the registered current-origin remote owner")
    func completeDemandStartsOneRepositoryFetch() async throws {
        let remoteProvider = PipelineRemoteReferenceProviderFake()
        let origin = "https://example.com/org/repository.git"
        let pipeline = FilesystemGitPipeline(
            bus: EventBus<RuntimeEnvelope>(),
            registrationDiscoveryProvider: PipelineAcceptingRegistrationDiscoveryProvider(),
            gitWorkingTreeProvider: .stub { _ in
                GitWorkingTreeStatus(
                    summary: GitWorkingTreeSummary(
                        changed: 0,
                        staged: 0,
                        untracked: 0,
                        aheadCount: 2,
                        behindCount: 1,
                        hasUpstream: true
                    ),
                    branch: "main",
                    origin: origin
                )
            },
            remoteReferenceRefreshProvider: remoteProvider,
            fseventStreamClient: PipelineSilentFSEventStreamClient(),
            filesystemDebounceWindow: .zero,
            filesystemMaxFlushLatency: .zero,
            gitCoalescingWindow: .zero
        )
        await pipeline.start()
        let rootPath = FileManager.default.temporaryDirectory
            .appending(path: "pipeline-remote-reference-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootPath) }
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()

        await remoteProvider.configure(origin: origin)
        await pipeline.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
        await pipeline.applyScopeChange(.registerForgeRepo(repoId: repoId, remote: origin))
        await pipeline.setRepositoryFactDemand(
            RepositoryFactDemandSnapshot(
                activePaneWorktreeId: worktreeId,
                sidebarAttendedWorktreeIds: [worktreeId],
                visibleActiveTabWorktreeIds: [worktreeId],
                openWorktreeIds: [worktreeId],
                repositoryIdByWorktreeId: [worktreeId: repoId],
                warmRepositoryIds: [repoId],
                unknownRepositoryIds: [],
                locallyInactiveRepositoryIds: [],
                warmAutomaticWorktreeIds: [worktreeId],
                unknownWorktreeIds: [],
                backgroundOnlyAutomaticWorktreeIds: [],
                locallyInactiveWorktreeIds: []
            )
        )
        await remoteProvider.waitForStageCount(1)
        await remoteProvider.waitForCleanupCount(1)

        #expect(await remoteProvider.stageCount == 1)
        #expect(await remoteProvider.promoteCount == 1)
        #expect(await remoteProvider.maximumConcurrentPromotionCount == 1)

        await pipeline.setRepositoryFactDemand(.empty)
        await pipeline.shutdown()
    }

    @Test("production adapter promotes remote refs without mutating checked-out HEAD")
    func productionAdapterStagesThenPromotesDisposableRemote() async throws {
        let sourceRepository = try FilesystemTestGitRepo.create(named: "remote-adapter-source")
        let fixtureRoot = sourceRepository.deletingLastPathComponent()
        let bareRemote = fixtureRoot.appending(
            path: "remote-adapter-bare-\(UUIDv7.generate().uuidString).git",
            directoryHint: .isDirectory
        )
        let localClone = fixtureRoot.appending(
            path: "remote-adapter-clone-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        defer {
            FilesystemTestGitRepo.destroy(sourceRepository)
            FilesystemTestGitRepo.destroy(bareRemote)
            FilesystemTestGitRepo.destroy(localClone)
        }

        try "first\n".write(
            to: sourceRepository.appending(path: "tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try FilesystemTestGitRepo.runGit(at: sourceRepository, args: ["add", "tracked.txt"])
        try FilesystemTestGitRepo.runGit(at: sourceRepository, args: ["commit", "-m", "Initial remote state"])
        try FilesystemTestGitRepo.runGit(
            at: fixtureRoot,
            args: ["clone", "--bare", sourceRepository.path, bareRemote.path]
        )
        try FilesystemTestGitRepo.runGit(at: fixtureRoot, args: ["clone", bareRemote.path, localClone.path])
        let initialCanonicalOID = try FilesystemTestGitRepo.runGit(
            at: localClone,
            args: ["rev-parse", "refs/remotes/origin/main"]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let checkedOutHeadOID = try FilesystemTestGitRepo.runGit(
            at: localClone,
            args: ["rev-parse", "HEAD"]
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        try "first\nsecond\n".write(
            to: sourceRepository.appending(path: "tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try FilesystemTestGitRepo.runGit(at: sourceRepository, args: ["add", "tracked.txt"])
        try FilesystemTestGitRepo.runGit(at: sourceRepository, args: ["commit", "-m", "Updated remote state"])
        try FilesystemTestGitRepo.runGit(
            at: sourceRepository,
            args: ["remote", "add", "origin", bareRemote.path]
        )
        try FilesystemTestGitRepo.runGit(at: sourceRepository, args: ["push", "origin", "main"])
        let expectedPromotedOID = try FilesystemTestGitRepo.runGit(
            at: sourceRepository,
            args: ["rev-parse", "HEAD"]
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let provider = AgentStudioGitRemoteReferenceRefreshProvider(
            client: SystemGitRemoteClient(
                configuration: .init(allowedProtocols: [.file])
            )
        )
        let snapshot = try await provider.captureRemoteTrackingSnapshot(
            repositoryPath: localClone,
            remoteName: "origin"
        )
        let stagedFetch = try await provider.stageFetch(
            snapshot: snapshot,
            stagingId: UUIDv7.generate()
        )
        let canonicalOIDBeforePromotion = try FilesystemTestGitRepo.runGit(
            at: localClone,
            args: ["rev-parse", "refs/remotes/origin/main"]
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(!stagedFetch.updates.isEmpty)
        #expect(canonicalOIDBeforePromotion == initialCanonicalOID)
        try await provider.promoteStagedFetch(stagedFetch)

        let canonicalOIDAfterPromotion = try FilesystemTestGitRepo.runGit(
            at: localClone,
            args: ["rev-parse", "refs/remotes/origin/main"]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let checkedOutHeadOIDAfterPromotion = try FilesystemTestGitRepo.runGit(
            at: localClone,
            args: ["rev-parse", "HEAD"]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(canonicalOIDAfterPromotion == expectedPromotedOID)
        #expect(checkedOutHeadOIDAfterPromotion == checkedOutHeadOID)
        try await provider.cleanupStagedFetch(stagedFetch.handle)
        let retainedStagingRefs = try FilesystemTestGitRepo.runGit(
            at: localClone,
            args: ["for-each-ref", "--format=%(refname)", stagedFetch.handle.stagingNamespace]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(retainedStagingRefs.isEmpty)
    }
}

private actor PipelineRemoteReferenceProviderFake: RemoteReferenceRefreshProviding {
    private var origin = "https://example.com/unconfigured.git"
    private var stageCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var cleanupCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var stageCount = 0
    private(set) var promoteCount = 0
    private(set) var cleanupCount = 0
    private var activePromotionCount = 0
    private(set) var maximumConcurrentPromotionCount = 0

    func configure(origin: String) {
        self.origin = origin
    }

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
        stageCount += 1
        resumeStageWaiters()
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
        promoteCount += 1
        activePromotionCount += 1
        maximumConcurrentPromotionCount = max(maximumConcurrentPromotionCount, activePromotionCount)
        activePromotionCount -= 1
    }

    func cleanupStagedFetch(_: GitStagedFetchHandle) async throws {
        cleanupCount += 1
        resumeCleanupWaiters()
    }

    func cleanupAbandonedStagedFetches(
        repositoryCommonDirectory _: URL,
        retainedStagingIds _: Set<UUID>
    ) async throws {}

    func waitForStageCount(_ expectedCount: Int) async {
        guard stageCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            stageCountWaiters.append((expectedCount, continuation))
        }
    }

    func waitForCleanupCount(_ expectedCount: Int) async {
        guard cleanupCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            cleanupCountWaiters.append((expectedCount, continuation))
        }
    }

    private func resumeStageWaiters() {
        let ready = stageCountWaiters.filter { $0.0 <= stageCount }
        stageCountWaiters.removeAll { $0.0 <= stageCount }
        for (_, continuation) in ready { continuation.resume() }
    }

    private func resumeCleanupWaiters() {
        let ready = cleanupCountWaiters.filter { $0.0 <= cleanupCount }
        cleanupCountWaiters.removeAll { $0.0 <= cleanupCount }
        for (_, continuation) in ready { continuation.resume() }
    }
}

private struct PipelineAcceptingRegistrationDiscoveryProvider: RepoScanner.GitRepositoryDiscoveryProvider {
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

private final class PipelineSilentFSEventStreamClient: FSEventStreamClient, @unchecked Sendable {
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
