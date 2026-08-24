import AgentStudioGit
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("GitWorkingDirectoryProjector remote-reference currentness")
struct GitWorkingDirectoryProjectorRemoteReferenceTests {
    @Test("matching accepted origin preserves ahead and behind")
    func matchingOriginPreservesCounts() {
        let status = makeStatus()

        let projected = GitWorkingDirectoryProjector.statusWithCurrentRemoteReferenceAuthority(
            status,
            acceptedOrigin: "https://example.com/org/repo.git",
            currentOrigin: "https://example.com/org/repo.git"
        )

        #expect(projected == status)
    }

    @Test("missing or wrong accepted origin suppresses only ahead and behind")
    func wrongOriginSuppressesRemoteCounts() {
        let status = makeStatus()

        let projected = GitWorkingDirectoryProjector.statusWithCurrentRemoteReferenceAuthority(
            status,
            acceptedOrigin: "https://example.com/org/old.git",
            currentOrigin: "https://example.com/org/repo.git"
        )

        #expect(projected.summary.aheadCount == nil)
        #expect(projected.summary.behindCount == nil)
        #expect(projected.summary.changed == status.summary.changed)
        #expect(projected.summary.staged == status.summary.staged)
        #expect(projected.summary.untracked == status.summary.untracked)
        #expect(projected.summary.linesAdded == status.summary.linesAdded)
        #expect(projected.summary.linesDeleted == status.summary.linesDeleted)
        #expect(projected.summary.hasUpstream == status.summary.hasUpstream)
        #expect(projected.branch == status.branch)
        #expect(projected.originResolution == status.originResolution)
    }

    @Test("authority revisions reject callbacks that arrive after invalidation")
    func authorityRevisionRejectsStaleCallbacks() async {
        let actor = GitWorkingDirectoryProjector(
            bus: EventBus<RuntimeEnvelope>(),
            gitWorkingTreeProvider: StubGitWorkingTreeStatusProvider { _ in nil },
            coalescingWindow: .zero
        )
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()
        let rootPath = URL(filePath: "/tmp/remote-reference-authority", directoryHint: .isDirectory)
        let origin = "https://example.com/org/repo.git"
        await actor.assertTopology(
            FilesystemTopologyAssertion(
                generation: 1,
                contextsByWorktreeId: [
                    worktreeId: WorktreeFilesystemContext(repoId: repoId, rootPath: rootPath)
                ]
            )
        )
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
        let staleAcceptance = makeAcceptance(
            repoId: repoId,
            origin: origin,
            rootPath: rootPath,
            authorityRevision: 1
        )
        let currentAcceptance = makeAcceptance(
            repoId: repoId,
            origin: origin,
            rootPath: rootPath,
            authorityRevision: 3
        )

        await actor.applyRemoteReferenceAuthorityUpdate(.localAccepted(staleAcceptance))
        #expect(await !actor.immediateRefreshWorktreeIds.contains(worktreeId))
        await actor.applyRemoteReferenceAuthorityUpdate(
            .invalidated(repoId: repoId, topologyGeneration: 2, authorityRevision: 2)
        )
        await actor.applyRemoteReferenceAuthorityUpdate(.localAccepted(staleAcceptance))
        #expect(await actor.remoteReferenceAcceptanceByRepoId[repoId] == nil)

        await actor.applyRemoteReferenceAuthorityUpdate(.localAccepted(currentAcceptance))
        await actor.applyRemoteReferenceAuthorityUpdate(
            .invalidated(repoId: repoId, topologyGeneration: 2, authorityRevision: 2)
        )
        #expect(await actor.remoteReferenceAcceptanceByRepoId[repoId] == currentAcceptance)

        let promotedAcceptance = makeAcceptance(
            repoId: repoId,
            origin: origin,
            rootPath: rootPath,
            authorityRevision: 4
        )
        await actor.applyRemoteReferenceAuthorityUpdate(
            .promoted(promotedAcceptance, representedWorktreeIds: [worktreeId])
        )
        #expect(await actor.immediateRefreshWorktreeIds.contains(worktreeId))
        await actor.shutdown()
    }

    private func makeStatus() -> GitWorkingTreeStatus {
        GitWorkingTreeStatus(
            summary: GitWorkingTreeSummary(
                changed: 3,
                staged: 2,
                untracked: 1,
                linesAdded: 12,
                linesDeleted: 4,
                aheadCount: 5,
                behindCount: 6,
                hasUpstream: true
            ),
            branch: "main",
            originResolution: .resolved("https://example.com/org/repo.git")
        )
    }

    private func makeAcceptance(
        repoId: UUID,
        origin: String,
        rootPath: URL,
        authorityRevision: UInt64
    ) -> RemoteReferenceAcceptance {
        RemoteReferenceAcceptance(
            repoId: repoId,
            expectedOrigin: origin,
            topologyGeneration: 1,
            authorityRevision: authorityRevision,
            snapshot: GitRemoteTrackingSnapshot(
                repositoryPath: rootPath,
                repositoryCommonDirectory: rootPath.appending(path: ".git"),
                remoteName: "origin",
                configuredRemoteURL: origin,
                effectiveFetchURL: origin,
                references: []
            )
        )
    }
}
