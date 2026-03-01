import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class CanonicalModelTests {

    @Test
    func canonicalRepo_hasStableIdentityFieldsOnly() {
        let repoId = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

        let repo = CanonicalRepo(
            id: repoId,
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            createdAt: createdAt
        )

        #expect(repo.id == repoId)
        #expect(repo.name == "agent-studio")
        #expect(repo.repoPath.path == "/tmp/agent-studio")
        #expect(repo.createdAt == createdAt)
        #expect(!repo.stableKey.isEmpty)
    }

    @Test
    func canonicalWorktree_linksToRepoIdentity() {
        let repoId = UUID()
        let worktree = CanonicalWorktree(
            repoId: repoId,
            name: "feature-runtime-envelope",
            path: URL(fileURLWithPath: "/tmp/agent-studio-feature"),
            isMainWorktree: false
        )

        #expect(worktree.repoId == repoId)
        #expect(worktree.name == "feature-runtime-envelope")
        #expect(worktree.path.path == "/tmp/agent-studio-feature")
        #expect(worktree.isMainWorktree == false)
        #expect(!worktree.stableKey.isEmpty)
    }

    @Test
    func repoEnrichment_holdsDerivedRepoMetadata() {
        let repoId = UUID()
        let enrichment = RepoEnrichment.resolved(
            repoId: repoId,
            raw: RawRepoOrigin(
                origin: "git@github.com:askluna/agent-studio.git",
                upstream: "git@github.com:upstream/agent-studio.git"
            ),
            identity: RepoIdentity(
                groupKey: "remote:askluna/agent-studio",
                remoteSlug: "askluna/agent-studio",
                organizationName: "askluna",
                displayName: "agent-studio"
            ),
            updatedAt: Date()
        )

        #expect(enrichment.repoId == repoId)
        #expect(enrichment.organizationName == "askluna")
        #expect(enrichment.remoteSlug == "askluna/agent-studio")
        #expect(enrichment.groupKey == "remote:askluna/agent-studio")
    }

    @Test
    func worktreeEnrichment_holdsDerivedWorktreeMetadata() {
        let repoId = UUID()
        let worktreeId = UUID()
        let enrichment = WorktreeEnrichment(
            worktreeId: worktreeId,
            repoId: repoId,
            branch: "main",
            isMainWorktree: true,
            snapshot: nil
        )

        #expect(enrichment.worktreeId == worktreeId)
        #expect(enrichment.repoId == repoId)
        #expect(enrichment.branch == "main")
        #expect(enrichment.isMainWorktree)
        #expect(enrichment.snapshot == nil)
    }
}
