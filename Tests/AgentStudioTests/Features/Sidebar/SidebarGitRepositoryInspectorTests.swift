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
}
