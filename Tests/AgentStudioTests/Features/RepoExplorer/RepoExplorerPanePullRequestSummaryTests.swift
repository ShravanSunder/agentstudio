import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@Suite
struct RepoExplorerPanePullRequestSummaryTests {
    struct SummaryOracle: Sendable {
        let state: PullRequestSummaryState
        let header: String
        let chipText: String
        let tone: PaneContextChipTone
    }
    static let summaries: [SummaryOracle] = [
        .init(state: .needsAttention(count: 1), header: "Needs attention (1)", chipText: "2 ✗", tone: .danger),
        .init(state: .running, header: "Running", chipText: "2 ◌", tone: .info),
        .init(state: .allGood, header: "All good", chipText: "2 ✓", tone: .success),
        .init(state: .noInfo, header: "No PR info", chipText: "2", tone: .neutral),
    ]
    @Test(arguments: summaries)
    func summaryRowUsesTheDeclaredStateAndPreparedSharedChip(_ oracle: SummaryOracle) throws {
        let pane = UUIDv7.generate()
        let summary = PullRequestSummaryDetail.summary(
            .init(
                state: oracle.state,
                members: [
                    .pullRequest(worktreeId: UUIDv7.generate(), number: 7, checks: .failed, review: .changesRequested),
                    .unknown(worktreeId: UUIDv7.generate()),
                ]))
        let display = PaneContextDisplay(
            revision: .init(1), agentTitle: nil, agentLine: nil, own: .zero,
            includingDrawers: .zero, pullRequests: summary)
        let snapshot = RepoExplorerSnapshot(
            repos: [], repoEnrichmentByRepoId: [:], surface: .panes, query: "",
            unassociatedPaneLocations: [
                .init(paneId: pane, tabId: UUIDv7.generate(), tabIndex: 0, paneIndexInTab: 0, isActiveInTab: false)
            ])
        let facts = RepoExplorerPaneRowFacts(
            terminalTitle: "Pane", contextDisplay: display, latestMessageText: nil,
            recencyReferenceDate: .distantPast, recencyText: "—", isActive: false)
        let projection = RepoExplorerProjection.project(snapshot, paneRowFactsByPaneId: [pane: facts])
        let row = try #require(projection.resolvedGroups.flatMap { projection.paneRowsByGroupId[$0.id] ?? [] }.first)
        let chip = try #require(row.pullRequestSummaryChip)
        #expect(chip.presentation.header == oracle.header)
        #expect(chip.presentation.chipText == oracle.chipText)
        #expect(chip.presentation.tone == oracle.tone)
        #expect(chip.control.tooltip.text == oracle.header)
        #expect(row.variants?.compact.chips == [.gitPR, .clock])
        #expect(row.variants?.compact.fallbackLineCount == row.variants?.expanded.fallbackLineCount)
    }
    @Test
    func notApplicablePreservesTodaysSinglePRAndLoadingChip() {
        #expect(RepoExplorerPanePullRequestProjection.make(.notApplicable) == nil)
        let states: [GitBranchStatus] = [
            .init(
                isDirty: false, syncState: .noUpstream, prCount: 1, linesAdded: 0, linesDeleted: 0,
                untrackedFileCount: 0),
            .init(
                isDirty: false, syncState: .noUpstream, prCount: 1, pullRequestIsLoading: true, linesAdded: 0,
                linesDeleted: 0, untrackedFileCount: 0),
            .init(
                isDirty: false, syncState: .noUpstream, prCount: nil, pullRequestIsLoading: true, linesAdded: 0,
                linesDeleted: 0, untrackedFileCount: 0),
            .init(
                isDirty: false, syncState: .noUpstream, prCount: 1, pullRequestDataUnavailable: true, linesAdded: 0,
                linesDeleted: 0, untrackedFileCount: 0),
        ]
        let expected: [SidebarPullRequestChipSpec.Presentation] = [
            .accent(count: 1), .neutral(count: 1), .neutral(count: nil), .hidden,
        ]
        for (status, expected) in zip(states, expected) {
            #expect(
                SidebarPullRequestChipSpec.presentation(branchStatus: status, usesPanesLoadingChip: true) == expected)
            let variant = RepoExplorerPaneRowVariants.make(
                title: "Pane", branchContext: nil, note: nil, isDrawer: false,
                branchStatus: status, isActive: false, hasPullRequestSummary: false)
            #expect(variant.compact.chips == (expected == .hidden ? [.clock] : [.gitPR, .clock]))
        }
    }

    @Test
    func summaryReplacesOnlyThePRSlotAndKeepsSelectedCheckoutChanges() {
        let status = GitBranchStatus(
            isDirty: true, syncState: .ahead(2), prCount: 1,
            linesAdded: 3, linesDeleted: 1, untrackedFileCount: 0)
        let variants = RepoExplorerPaneRowVariants.make(
            title: "Pane", branchContext: nil, note: nil,
            isDrawer: false, branchStatus: status, isActive: false, hasPullRequestSummary: true)
        #expect(variants.compact.chips == [.gitPR, .clock])
        #expect(variants.expanded.chips == [.gitPR, .changes, .sync, .clock])
        #expect(
            !SidebarGitStatusChips.hasContent(
                branchStatus: status, usesPanesLoadingChip: true,
                showsDetailedGitChips: false, showsPullRequestChip: false))
        #expect(
            SidebarGitStatusChips.hasContent(
                branchStatus: status, usesPanesLoadingChip: true,
                showsDetailedGitChips: true, showsPullRequestChip: false))
    }

}
