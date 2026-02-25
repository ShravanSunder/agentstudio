import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct SidebarGitRepositoryInspectorTests {

    @Test
    func makeRepoDisplayName_formatsRepoAndOrganization() {
        let title = GitRepositoryInspector.makeRepoDisplayName(
            fallbackName: "local-folder-name",
            remoteSlug: "shravansunder/agent-studio"
        )

        #expect(title == "agent-studio · shravansunder")
    }

    @Test
    func makeRepoDisplayName_formatsNestedOrganizationPath() {
        let title = GitRepositoryInspector.makeRepoDisplayName(
            fallbackName: "local-folder-name",
            remoteSlug: "company/platform/agent-studio"
        )

        #expect(title == "agent-studio · company/platform")
    }

    @Test
    func makeRepoDisplayName_fallsBackToFolderNameWhenOrgMissing() {
        let title = GitRepositoryInspector.makeRepoDisplayName(
            fallbackName: "askluna-finance",
            remoteSlug: "agent-studio"
        )

        #expect(title == "askluna-finance")
    }

    @Test
    func makeRepoDisplayName_fallsBackToFolderNameWhenRemoteMissing() {
        let title = GitRepositoryInspector.makeRepoDisplayName(
            fallbackName: "askluna-finance",
            remoteSlug: nil
        )

        #expect(title == "askluna-finance")
    }

    @Test
    func pullRequestLookupCandidates_prefersUpstreamAndAddsForkHeadRef() {
        let candidates = GitRepositoryInspector.pullRequestLookupCandidates(
            branch: "feature/sidebar-pr-chip",
            upstreamRepoSlug: "upstream-org/agentstudio",
            originRepoSlug: "ShravanSunder/agentstudio"
        )

        #expect(candidates.count == 3)
        #expect(
            candidates[0]
                == PullRequestLookupCandidate(repoSlug: "upstream-org/agentstudio", headRef: "feature/sidebar-pr-chip"))
        #expect(
            candidates[1]
                == PullRequestLookupCandidate(
                    repoSlug: "upstream-org/agentstudio", headRef: "ShravanSunder:feature/sidebar-pr-chip"))
        #expect(
            candidates[2]
                == PullRequestLookupCandidate(repoSlug: "ShravanSunder/agentstudio", headRef: "feature/sidebar-pr-chip")
        )
    }

    @Test
    func pullRequestLookupCandidates_stripsLocalRefsPrefix() {
        let candidates = GitRepositoryInspector.pullRequestLookupCandidates(
            branch: "refs/heads/ui-fixes-common-2",
            upstreamRepoSlug: nil,
            originRepoSlug: "ShravanSunder/agentstudio"
        )

        #expect(candidates.count == 1)
        #expect(
            candidates[0]
                == PullRequestLookupCandidate(repoSlug: "ShravanSunder/agentstudio", headRef: "ui-fixes-common-2"))
    }

    @Test
    func pullRequestLookupCandidates_dedupesMatchingOriginAndUpstream() {
        let candidates = GitRepositoryInspector.pullRequestLookupCandidates(
            branch: "ui-fixes-common-2",
            upstreamRepoSlug: "ShravanSunder/agentstudio",
            originRepoSlug: "ShravanSunder/agentstudio"
        )

        #expect(candidates.count == 1)
        #expect(
            candidates[0]
                == PullRequestLookupCandidate(repoSlug: "ShravanSunder/agentstudio", headRef: "ui-fixes-common-2"))
    }

    @Test
    func pullRequestLookupCandidates_returnsEmptyForWhitespaceBranch() {
        let candidates = GitRepositoryInspector.pullRequestLookupCandidates(
            branch: "   ",
            upstreamRepoSlug: "ShravanSunder/agentstudio",
            originRepoSlug: nil
        )

        #expect(candidates.isEmpty)
    }

    @Test
    func deduplicatedPRLookupWorktrees_collapsesEquivalentPaths() {
        let basePath = URL(fileURLWithPath: "/tmp/agentstudio")
        let equivalentPath = URL(fileURLWithPath: "/tmp/agentstudio/./")
        let distinctPath = URL(fileURLWithPath: "/tmp/agentstudio-2")

        let worktrees = [
            WorktreeStatusInput(worktreeId: UUID(), path: basePath, branch: "main"),
            WorktreeStatusInput(worktreeId: UUID(), path: equivalentPath, branch: "feature"),
            WorktreeStatusInput(worktreeId: UUID(), path: distinctPath, branch: "main"),
        ]

        let deduplicated = GitRepositoryInspector.deduplicatedPRLookupWorktrees(worktrees)
        #expect(deduplicated.count == 2)

        let normalized = Set(deduplicated.map { GitRepositoryInspector.normalizedPRLookupWorktreePath($0.path) })
        #expect(normalized.contains(GitRepositoryInspector.normalizedPRLookupWorktreePath(basePath)))
        #expect(normalized.contains(GitRepositoryInspector.normalizedPRLookupWorktreePath(distinctPath)))
    }

    @Test
    func deduplicatedPRLookupWorktrees_keepsSingleEntryWhenAllSamePath() {
        let pathA = URL(fileURLWithPath: "/tmp/repo")
        let pathB = URL(fileURLWithPath: "/tmp/repo/")
        let pathC = URL(fileURLWithPath: "/tmp/repo/./")

        let worktrees = [
            WorktreeStatusInput(worktreeId: UUID(), path: pathA, branch: "main"),
            WorktreeStatusInput(worktreeId: UUID(), path: pathB, branch: "feature"),
            WorktreeStatusInput(worktreeId: UUID(), path: pathC, branch: "bugfix"),
        ]

        let deduplicated = GitRepositoryInspector.deduplicatedPRLookupWorktrees(worktrees)
        #expect(deduplicated.count == 1)
    }
}
