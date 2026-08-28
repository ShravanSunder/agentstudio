import AgentStudioGit
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("Remote reference repository cardinality")
struct RemoteReferenceRepositoryCardinalityTests {
    @Test("one repository fetch promotes one token for every represented worktree")
    func oneRepositoryFetchPromotesOneTokenForEveryRepresentedWorktree() async throws {
        let repoId = UUIDv7.generate()
        let primaryWorktreeId = UUIDv7.generate()
        let linkedWorktreeId = UUIDv7.generate()
        let fixtureRoot = URL(
            filePath: "/tmp/remote-reference-repository-cardinality",
            directoryHint: .isDirectory
        )
        let primaryRoot = fixtureRoot.appending(path: "primary", directoryHint: .isDirectory)
        let linkedRoot = fixtureRoot.appending(path: "linked", directoryHint: .isDirectory)
        let sharedGitDirectory = primaryRoot.appending(path: ".git", directoryHint: .isDirectory)
        let origin = "https://example.com/owner/repository.git"
        let provider = RepositoryCardinalityRemoteReferenceProvider(
            expectedOrigin: origin,
            sharedGitDirectory: sharedGitDirectory
        )
        let authorityRecorder = RepositoryCardinalityAuthorityRecorder()
        let actor = RemoteReferenceRefreshActor(
            provider: provider,
            onAuthorityUpdate: { update in
                await authorityRecorder.record(update)
            }
        )
        let primaryContext = WorktreeFilesystemContext(repoId: repoId, rootPath: primaryRoot)
        let linkedContext = WorktreeFilesystemContext(repoId: repoId, rootPath: linkedRoot)

        await actor.register(
            repoId: repoId,
            worktreeId: primaryWorktreeId,
            repositoryPath: primaryRoot,
            remoteName: "origin",
            expectedOrigin: origin
        )
        await actor.assertTopology([
            primaryWorktreeId: primaryContext,
            linkedWorktreeId: linkedContext,
        ])
        await actor.setDemand(repositoryIds: [repoId])
        await actor.waitUntilIdle()

        #expect(await provider.stageCount == 1)
        #expect(await provider.promotionCount == 1)
        #expect(await provider.stagedRepositoryPaths == [primaryRoot])
        #expect(await provider.stagedCommonDirectories == [sharedGitDirectory])
        let promotedUpdate = try #require(await authorityRecorder.promotedUpdates.only)
        #expect(promotedUpdate.acceptance.repoId == repoId)
        #expect(promotedUpdate.acceptance.expectedOrigin == origin)
        #expect(promotedUpdate.representedWorktreeIds == [primaryWorktreeId, linkedWorktreeId])

        await actor.assertTopology([
            linkedWorktreeId: linkedContext,
            primaryWorktreeId: primaryContext,
        ])
        await actor.waitUntilIdle()

        #expect(await provider.stageCount == 1)
        #expect(await provider.promotionCount == 1)
        #expect(await authorityRecorder.promotedUpdates.count == 1)
        await actor.shutdown()
    }

    @Test("one promoted repository token recomputes every represented worktree")
    func onePromotedRepositoryTokenRecomputesEveryRepresentedWorktree() async {
        let repoId = UUIDv7.generate()
        let primaryWorktreeId = UUIDv7.generate()
        let linkedWorktreeId = UUIDv7.generate()
        let primaryRoot = URL(
            filePath: "/tmp/remote-reference-recompute/primary",
            directoryHint: .isDirectory
        )
        let linkedRoot = URL(
            filePath: "/tmp/remote-reference-recompute/linked",
            directoryHint: .isDirectory
        )
        let origin = "https://example.com/owner/repository.git"
        let actor = GitWorkingDirectoryProjector(
            bus: EventBus<RuntimeEnvelope>(),
            gitWorkingTreeProvider: StubGitWorkingTreeStatusProvider { _ in nil },
            coalescingWindow: .zero
        )
        await actor.assertTopology(
            FilesystemTopologyAssertion(
                generation: 1,
                contextsByWorktreeId: [
                    primaryWorktreeId: WorktreeFilesystemContext(repoId: repoId, rootPath: primaryRoot),
                    linkedWorktreeId: WorktreeFilesystemContext(repoId: repoId, rootPath: linkedRoot),
                ]
            )
        )
        for (worktreeId, rootPath) in [
            (primaryWorktreeId, primaryRoot),
            (linkedWorktreeId, linkedRoot),
        ] {
            _ = await actor.prepareRemoteReferenceCurrentStatus(
                GitWorkingTreeStatus(
                    summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                    branch: "main",
                    origin: origin
                ),
                changeset: FileChangeset(
                    worktreeId: worktreeId,
                    repoId: repoId,
                    rootPath: rootPath,
                    paths: [".git/config"],
                    containsGitInternalChanges: true,
                    timestamp: ContinuousClock().now,
                    batchSeq: 1
                )
            )
        }
        let acceptance = RemoteReferenceAcceptance(
            repoId: repoId,
            expectedOrigin: origin,
            topologyGeneration: 1,
            authorityRevision: 1,
            snapshot: GitRemoteTrackingSnapshot(
                repositoryPath: primaryRoot,
                repositoryCommonDirectory: primaryRoot.appending(
                    path: ".git",
                    directoryHint: .isDirectory
                ),
                remoteName: "origin",
                configuredRemoteURL: origin,
                effectiveFetchURL: origin,
                references: []
            )
        )

        await actor.applyRemoteReferenceAuthorityUpdate(
            .promoted(
                acceptance,
                representedWorktreeIds: [linkedWorktreeId, primaryWorktreeId]
            )
        )

        #expect(
            await actor.immediateRefreshWorktreeIds
                == [primaryWorktreeId, linkedWorktreeId]
        )
        await actor.shutdown()
    }
}

private actor RepositoryCardinalityAuthorityRecorder {
    struct PromotedUpdate: Sendable {
        let acceptance: RemoteReferenceAcceptance
        let representedWorktreeIds: Set<UUID>
    }

    private(set) var promotedUpdates: [PromotedUpdate] = []

    func record(_ update: RemoteReferenceAuthorityUpdate) {
        guard case .promoted(let acceptance, let representedWorktreeIds) = update else { return }
        promotedUpdates.append(
            PromotedUpdate(
                acceptance: acceptance,
                representedWorktreeIds: representedWorktreeIds
            )
        )
    }
}

private actor RepositoryCardinalityRemoteReferenceProvider: RemoteReferenceRefreshProviding {
    private let expectedOrigin: String
    private let sharedGitDirectory: URL

    private(set) var stageCount = 0
    private(set) var promotionCount = 0
    private(set) var stagedRepositoryPaths: [URL] = []
    private(set) var stagedCommonDirectories: [URL] = []

    init(expectedOrigin: String, sharedGitDirectory: URL) {
        self.expectedOrigin = expectedOrigin
        self.sharedGitDirectory = sharedGitDirectory
    }

    func captureRemoteTrackingSnapshot(
        repositoryPath: URL,
        remoteName: String
    ) async throws -> GitRemoteTrackingSnapshot {
        GitRemoteTrackingSnapshot(
            repositoryPath: repositoryPath,
            repositoryCommonDirectory: sharedGitDirectory,
            remoteName: remoteName,
            configuredRemoteURL: expectedOrigin,
            effectiveFetchURL: expectedOrigin,
            references: []
        )
    }

    func stageFetch(
        snapshot: GitRemoteTrackingSnapshot,
        stagingId: UUID
    ) async throws -> GitStagedFetchResult {
        stageCount += 1
        stagedRepositoryPaths.append(snapshot.repositoryPath)
        stagedCommonDirectories.append(snapshot.repositoryCommonDirectory)
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
        promotionCount += 1
    }

    func cleanupStagedFetch(_: GitStagedFetchHandle) async throws {}

    func cleanupAbandonedStagedFetches(
        repositoryCommonDirectory _: URL,
        retainedStagingIds _: Set<UUID>
    ) async {}
}

extension Collection {
    fileprivate var only: Element? {
        count == 1 ? first : nil
    }
}
