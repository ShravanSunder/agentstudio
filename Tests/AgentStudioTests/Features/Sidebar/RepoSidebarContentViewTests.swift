import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("RepoSidebarContentView")
struct RepoSidebarContentViewTests {
    @Test("branchStatus maps centralized local-git summary + PR count")
    func branchStatusMapsLocalSummaryAndPRCount() {
        let worktreeId = UUID()
        let snapshot = WorkspaceGitStatusStore.WorktreeSnapshot(
            worktreeId: worktreeId,
            summary: GitStatusSummary(changed: 1, staged: 0, untracked: 2),
            branch: "feature/sidebar",
            lastSequence: 5,
            timestamp: ContinuousClock().now
        )

        let status = RepoSidebarContentView.branchStatus(
            localSnapshot: snapshot,
            pullRequestCount: 3
        )

        #expect(status.isDirty == true)
        #expect(status.prCount == 3)
        #expect(status.syncState == .unknown)
        #expect(status.linesAdded == 0)
        #expect(status.linesDeleted == 0)
    }

    @Test("branchStatus keeps unknown local state when snapshot missing")
    func branchStatusFallsBackToUnknownWithoutLocalSnapshot() {
        let status = RepoSidebarContentView.branchStatus(
            localSnapshot: nil,
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

        let merged = RepoSidebarContentView.mergeBranchStatuses(
            localSnapshotsByWorktreeId: [
                localOnlyWorktreeId: WorkspaceGitStatusStore.WorktreeSnapshot(
                    worktreeId: localOnlyWorktreeId,
                    summary: GitStatusSummary(changed: 0, staged: 1, untracked: 0),
                    branch: nil,
                    lastSequence: 1,
                    timestamp: ContinuousClock().now
                )
            ],
            pullRequestCountsByWorktreeId: [prOnlyWorktreeId: 2]
        )

        #expect(merged[localOnlyWorktreeId]?.isDirty == true)
        #expect(merged[localOnlyWorktreeId]?.prCount == nil)
        #expect(merged[prOnlyWorktreeId]?.prCount == 2)
        #expect(merged[prOnlyWorktreeId]?.syncState == .unknown)
    }

    @Test("sidebar branch status derives from centralized workspace git snapshot ingestion")
    func sidebarBranchStatusDerivesFromWorkspaceGitStatusStoreSnapshots() {
        let worktreeId = UUID()
        let gitStatusStore = WorkspaceGitStatusStore()

        gitStatusStore.consume(
            makeFilesystemEnvelope(
                seq: 1,
                worktreeId: worktreeId,
                event: .gitStatusChanged(summary: GitStatusSummary(changed: 2, staged: 1, untracked: 0))
            )
        )
        gitStatusStore.consume(
            makeFilesystemEnvelope(
                seq: 2,
                worktreeId: worktreeId,
                event: .branchChanged(from: "main", to: "feature/sidebar-pipeline")
            )
        )

        let merged = RepoSidebarContentView.mergeBranchStatuses(
            localSnapshotsByWorktreeId: gitStatusStore.snapshotsByWorktreeId,
            pullRequestCountsByWorktreeId: [worktreeId: 5]
        )

        #expect(merged[worktreeId]?.isDirty == true)
        #expect(merged[worktreeId]?.prCount == 5)
        #expect(merged[worktreeId]?.syncState == .unknown)
    }

    private func makeFilesystemEnvelope(
        seq: UInt64,
        worktreeId: UUID,
        event: FilesystemEvent
    ) -> PaneEventEnvelope {
        PaneEventEnvelope(
            source: .system(.builtin(.filesystemWatcher)),
            sourceFacets: PaneContextFacets(worktreeId: worktreeId),
            paneKind: nil,
            seq: seq,
            commandId: nil,
            correlationId: nil,
            timestamp: ContinuousClock().now,
            epoch: 0,
            event: .filesystem(event)
        )
    }
}
