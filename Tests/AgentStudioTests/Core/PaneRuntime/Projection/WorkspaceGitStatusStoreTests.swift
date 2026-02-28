import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceGitStatusStore")
struct WorkspaceGitStatusStoreTests {
    @Test("git status + branch events merge into one worktree snapshot")
    func mergesStatusAndBranchEvents() {
        let store = WorkspaceGitStatusStore()
        let worktreeId = UUID()

        store.consume(
            makeFilesystemEnvelope(
                seq: 1,
                worktreeId: worktreeId,
                event: .gitStatusChanged(summary: GitStatusSummary(changed: 2, staged: 1, untracked: 3))
            )
        )

        store.consume(
            makeFilesystemEnvelope(
                seq: 2,
                worktreeId: worktreeId,
                event: .branchChanged(from: "main", to: "feature/filesystem")
            )
        )

        guard let snapshot = store.snapshotsByWorktreeId[worktreeId] else {
            Issue.record("Expected worktree snapshot to be created")
            return
        }

        #expect(snapshot.summary.changed == 2)
        #expect(snapshot.summary.staged == 1)
        #expect(snapshot.summary.untracked == 3)
        #expect(snapshot.branch == "feature/filesystem")
        #expect(snapshot.lastSequence == 2)
    }

    @Test("out-of-order events do not clobber latest snapshot")
    func ignoresOutOfOrderEnvelopes() {
        let store = WorkspaceGitStatusStore()
        let worktreeId = UUID()

        store.consume(
            makeFilesystemEnvelope(
                seq: 5,
                worktreeId: worktreeId,
                event: .branchChanged(from: "main", to: "feature/new")
            )
        )
        store.consume(
            makeFilesystemEnvelope(
                seq: 4,
                worktreeId: worktreeId,
                event: .gitStatusChanged(summary: GitStatusSummary(changed: 9, staged: 9, untracked: 9))
            )
        )

        guard let snapshot = store.snapshotsByWorktreeId[worktreeId] else {
            Issue.record("Expected snapshot to exist")
            return
        }

        #expect(snapshot.branch == "feature/new")
        #expect(snapshot.summary.changed == 0)
        #expect(snapshot.lastSequence == 5)
    }

    @Test("prune removes snapshots for detached worktrees")
    func pruneRemovesStaleWorktreeSnapshots() {
        let store = WorkspaceGitStatusStore()
        let keepWorktreeId = UUID()
        let dropWorktreeId = UUID()

        store.consume(
            makeFilesystemEnvelope(
                seq: 1,
                worktreeId: keepWorktreeId,
                event: .gitStatusChanged(summary: GitStatusSummary(changed: 1, staged: 0, untracked: 0))
            )
        )
        store.consume(
            makeFilesystemEnvelope(
                seq: 2,
                worktreeId: dropWorktreeId,
                event: .gitStatusChanged(summary: GitStatusSummary(changed: 0, staged: 1, untracked: 0))
            )
        )

        store.prune(validWorktreeIds: Set([keepWorktreeId]))

        #expect(store.snapshotsByWorktreeId[keepWorktreeId] != nil)
        #expect(store.snapshotsByWorktreeId[dropWorktreeId] == nil)
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
