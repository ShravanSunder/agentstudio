import AgentStudioCore
import Testing

@Suite("Repo Explorer pane chip presentation")
struct RepoExplorerPaneChipPresentationTests {
    @Test("loading PR facts use a neutral chip only on Panes")
    func loadingPresentationIsPanesOnly() {
        let loadingWithoutCount = branchStatus(count: nil, loading: true)
        let loadingWithCount = branchStatus(count: 2, loading: true)
        let readyWithCount = branchStatus(count: 2, loading: false)
        let unavailable = branchStatus(count: 2, loading: false, unavailable: true)

        #expect(
            SidebarPullRequestChipSpec.presentation(
                branchStatus: loadingWithoutCount,
                usesPanesLoadingChip: true
            ) == .neutral(count: nil)
        )
        #expect(
            SidebarPullRequestChipSpec.presentation(
                branchStatus: loadingWithCount,
                usesPanesLoadingChip: true
            ) == .neutral(count: 2)
        )
        #expect(
            SidebarPullRequestChipSpec.presentation(
                branchStatus: loadingWithoutCount,
                usesPanesLoadingChip: false
            ) == .hidden
        )
        #expect(
            SidebarPullRequestChipSpec.presentation(
                branchStatus: loadingWithCount,
                usesPanesLoadingChip: false
            ) == .accent(count: 2)
        )
        #expect(
            SidebarPullRequestChipSpec.presentation(
                branchStatus: readyWithCount,
                usesPanesLoadingChip: true
            ) == .accent(count: 2)
        )
        #expect(
            SidebarPullRequestChipSpec.presentation(
                branchStatus: unavailable,
                usesPanesLoadingChip: true
            ) == .hidden
        )
    }

    private func branchStatus(
        count: Int?,
        loading: Bool,
        unavailable: Bool = false
    ) -> GitBranchStatus {
        GitBranchStatus(
            isDirty: false,
            syncState: .synced,
            prCount: count,
            pullRequestIsLoading: loading,
            pullRequestDataUnavailable: unavailable,
            linesAdded: 0,
            linesDeleted: 0,
            untrackedFileCount: 0
        )
    }
}
