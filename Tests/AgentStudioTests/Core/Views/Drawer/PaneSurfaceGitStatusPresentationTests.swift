import Testing

@testable import AgentStudioCore

@Suite("Pane surface Git status presentation")
struct PaneSurfaceGitStatusPresentationTests {
    @Test("clean synchronized checkout has no drawer status")
    func cleanSynchronizedCheckoutHasNoDrawerStatus() {
        let presentation = PaneSurfaceGitStatusPresentation.resolve(
            branchStatus: GitBranchStatus(
                isDirty: false,
                syncState: .synced,
                prCount: nil,
                linesAdded: 0,
                linesDeleted: 0,
                untrackedFileCount: 0
            )
        )

        #expect(presentation == nil)
    }

    @Test("drawer status preserves only nonzero diff and sync facts")
    func drawerStatusPreservesOnlyNonzeroDiffAndSyncFacts() throws {
        let presentation = try #require(
            PaneSurfaceGitStatusPresentation.resolve(
                branchStatus: GitBranchStatus(
                    isDirty: true,
                    syncState: .diverged(ahead: 3, behind: 8),
                    prCount: nil,
                    linesAdded: 20,
                    linesDeleted: 14,
                    untrackedFileCount: 2
                )
            )
        )

        #expect(presentation.linesAdded == 20)
        #expect(presentation.linesDeleted == 14)
        #expect(presentation.showsUntrackedFiles == false)
        #expect(presentation.commitsAhead == 3)
        #expect(presentation.commitsBehind == 8)
        #expect(
            presentation.accessibilityLabel == "20 lines added, 14 lines deleted, 3 commits ahead, 8 commits behind")
    }

    @Test("zero directions and unavailable counts stay absent")
    func zeroDirectionsAndUnavailableCountsStayAbsent() throws {
        let behindOnly = try #require(
            PaneSurfaceGitStatusPresentation.resolve(
                branchStatus: GitBranchStatus(
                    isDirty: false,
                    syncState: .behind(625),
                    prCount: nil,
                    linesAdded: 0,
                    linesDeleted: 0,
                    untrackedFileCount: 0
                )
            )
        )

        #expect(behindOnly.linesAdded == nil)
        #expect(behindOnly.linesDeleted == nil)
        #expect(behindOnly.commitsAhead == nil)
        #expect(behindOnly.commitsBehind == 625)
        #expect(behindOnly.accessibilityLabel == "625 commits behind")
    }

    @Test("untracked-only checkout remains visible without inventing line counts")
    func untrackedOnlyCheckoutRemainsVisible() throws {
        let presentation = try #require(
            PaneSurfaceGitStatusPresentation.resolve(
                branchStatus: GitBranchStatus(
                    isDirty: true,
                    syncState: .synced,
                    prCount: nil,
                    linesAdded: 0,
                    linesDeleted: 0,
                    untrackedFileCount: 4
                )
            )
        )

        #expect(presentation.linesAdded == nil)
        #expect(presentation.linesDeleted == nil)
        #expect(presentation.showsUntrackedFiles)
        #expect(presentation.accessibilityLabel == "Untracked files")
    }
}
