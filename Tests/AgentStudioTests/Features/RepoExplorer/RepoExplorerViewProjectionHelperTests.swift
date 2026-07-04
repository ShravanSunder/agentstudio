import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("RepoExplorerViewProjectionHelperTests")
struct RepoExplorerViewProjectionHelperTests {
    @Test("source group icon uses same checkout color contract as worktree rows")
    func sourceGroupIconUsesCheckoutColorContract() {
        let repoId = UUID()
        let repo = RepoPresentationItem(
            id: repoId,
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            stableKey: "agent-studio",
            worktrees: [
                Worktree(
                    repoId: repoId,
                    name: "notification-inbox-redesign",
                    path: URL(fileURLWithPath: "/tmp/agent-studio.notification-inbox-redesign")
                )
            ]
        )
        let group = RepoPresentationGroup(
            id: "remote:ShravanSunder/agent-studio",
            repoTitle: "agent-studio",
            organizationName: "ShravanSunder",
            repos: [repo]
        )

        let icon = RepoExplorerView.sourceGroupIcon(for: group)

        let expectedColorHex = RepoPresentationColoring.checkoutColorHex(
            for: repo,
            in: group
        )

        if case .coloredRepo(let colorHex) = icon {
            #expect(colorHex == expectedColorHex)
        } else {
            Issue.record("Expected RepoExplorer group header to use colored repo source icon")
        }
    }

    @Test("source group icon uses semantic pane and tab colors outside repo grouping")
    func sourceGroupIconUsesSemanticPaneAndTabColorsOutsideRepoGrouping() {
        let group = RepoPresentationGroup(
            id: "pane:active",
            repoTitle: "Pane 1",
            organizationName: nil,
            repos: []
        )

        #expect(RepoExplorerView.sourceGroupIcon(for: group, groupingMode: .pane) == .paneGroup)
        #expect(RepoExplorerView.sourceGroupIcon(for: group, groupingMode: .tab) == .tabGroup)
    }

    @Test("group icon mode is taken from the applied projection snapshot")
    func groupIconModeIsTakenFromAppliedProjectionSnapshot() {
        let group = RepoPresentationGroup(
            id: "pane:active",
            repoTitle: "Pane 1",
            organizationName: nil,
            repos: []
        )

        #expect(RepoExplorerView.groupIcon(for: group, projectionGroupingMode: .pane) == .paneGroup)
        #expect(RepoExplorerView.groupIcon(for: group, projectionGroupingMode: .tab) == .tabGroup)
    }

    @Test("sort order changes have their own projection trigger")
    func sortOrderChangesHaveTheirOwnProjectionTrigger() {
        let repoId = UUID()
        let repo = RepoPresentationItem(
            id: repoId,
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            stableKey: "agent-studio",
            worktrees: [
                Worktree(
                    repoId: repoId,
                    name: "main",
                    path: URL(fileURLWithPath: "/tmp/agent-studio")
                )
            ]
        )
        let previous = RepoExplorerProjectionRequest(
            generation: 1,
            snapshot: RepoExplorerSnapshot(
                repos: [repo],
                repoEnrichmentByRepoId: [:],
                sortOrder: .ascending,
                query: ""
            ),
            expandedGroupIds: [],
            isFiltering: false,
            trigger: "startup_diagnostic"
        )
        let next = RepoExplorerProjectionRequest(
            generation: 2,
            snapshot: RepoExplorerSnapshot(
                repos: [repo],
                repoEnrichmentByRepoId: [:],
                sortOrder: .descending,
                query: ""
            ),
            expandedGroupIds: [],
            isFiltering: false,
            trigger: "startup_diagnostic"
        )

        #expect(RepoExplorerView.sidebarProjectionTrigger(previous: previous, next: next) == "sort_order")
    }

    @Test("branchStatus maps sync and line diff values from snapshot summary")
    func branchStatusMapsSnapshotSyncAndLineDiff() {
        let worktreeId = UUID()
        let repoId = UUID()
        let enrichment = WorktreeEnrichment(
            worktreeId: worktreeId,
            repoId: repoId,
            branch: "main",
            snapshot: GitWorkingTreeSnapshot(
                worktreeId: worktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/repo-\(UUID().uuidString)"),
                summary: GitWorkingTreeSummary(
                    changed: 2,
                    staged: 1,
                    untracked: 0,
                    linesAdded: 12,
                    linesDeleted: 3,
                    aheadCount: 1,
                    behindCount: 0,
                    hasUpstream: true
                ),
                branch: "main"
            )
        )

        let status = RepoExplorerView.branchStatus(
            enrichment: enrichment,
            pullRequestCount: 1
        )

        #expect(status.isDirty)
        #expect(status.linesAdded == 12)
        #expect(status.linesDeleted == 3)
        #expect(status.syncState == .ahead(1))
        #expect(status.prCount == 1)
    }

    @Test("branchStatus keeps unknown local state when snapshot missing")
    func branchStatusFallsBackToUnknownWithoutLocalSnapshot() {
        let status = RepoExplorerView.branchStatus(
            enrichment: nil,
            pullRequestCount: 7
        )

        #expect(status.isDirty == GitBranchStatus.unknown.isDirty)
        #expect(status.syncState == GitBranchStatus.unknown.syncState)
        #expect(status.prCount == 7)
    }

    @Test("mergeBranchStatuses merges local snapshots with independent PR counts")
    func mergeBranchStatusesMergesSources() {
        let localOnlyWorktreeId = UUID()
        let prOnlyWorktreeId = UUID()
        let repoId = UUID()

        let merged = RepoExplorerView.mergeBranchStatuses(
            worktreeEnrichmentsByWorktreeId: [
                localOnlyWorktreeId: WorktreeEnrichment(
                    worktreeId: localOnlyWorktreeId,
                    repoId: repoId,
                    branch: "",
                    snapshot: GitWorkingTreeSnapshot(
                        worktreeId: localOnlyWorktreeId,
                        rootPath: URL(fileURLWithPath: "/tmp/repo-\(UUID().uuidString)"),
                        summary: GitWorkingTreeSummary(changed: 0, staged: 1, untracked: 0),
                        branch: nil
                    )
                )
            ],
            pullRequestCountsByWorktreeId: [prOnlyWorktreeId: 2]
        )

        #expect(merged[localOnlyWorktreeId]?.isDirty == true)
        #expect(merged[localOnlyWorktreeId]?.prCount == nil)
        #expect(merged[prOnlyWorktreeId]?.prCount == 2)
        #expect(merged[prOnlyWorktreeId]?.syncState == .unknown)
    }

    @Test("sidebar branch status derives from worktree enrichment snapshots")
    func sidebarBranchStatusDerivesFromWorktreeEnrichmentSnapshots() {
        let worktreeId = UUID()
        let repoId = UUID()
        let enrichment = WorktreeEnrichment(
            worktreeId: worktreeId,
            repoId: repoId,
            branch: "feature/sidebar-pipeline",
            snapshot: GitWorkingTreeSnapshot(
                worktreeId: worktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/repo-\(UUID().uuidString)"),
                summary: GitWorkingTreeSummary(changed: 2, staged: 1, untracked: 0),
                branch: "feature/sidebar-pipeline"
            )
        )

        let merged = RepoExplorerView.mergeBranchStatuses(
            worktreeEnrichmentsByWorktreeId: [worktreeId: enrichment],
            pullRequestCountsByWorktreeId: [worktreeId: 5]
        )

        #expect(merged[worktreeId]?.isDirty == true)
        #expect(merged[worktreeId]?.prCount == 5)
        #expect(merged[worktreeId]?.syncState == .unknown)
    }
}
