import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceGitWorkingTreeStore")
struct WorkspaceGitWorkingTreeStoreTests {
    @Test("git snapshot + branch events merge into one worktree snapshot")
    func mergesSnapshotAndBranchEvents() {
        let store = WorkspaceGitWorkingTreeStore()
        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)")

        store.consume(
            makeFilesystemEnvelope(
                seq: 1,
                worktreeId: worktreeId,
                event: .gitSnapshotChanged(
                    snapshot: GitWorkingTreeSnapshot(
                        worktreeId: worktreeId,
                        rootPath: rootPath,
                        summary: GitWorkingTreeSummary(changed: 2, staged: 1, untracked: 3),
                        branch: "main"
                    )
                )
            )
        )

        store.consume(
            makeFilesystemEnvelope(
                seq: 2,
                worktreeId: worktreeId,
                event: .branchChanged(
                    worktreeId: worktreeId,
                    repoId: worktreeId,
                    from: "main",
                    to: "feature/filesystem"
                )
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
        let store = WorkspaceGitWorkingTreeStore()
        let worktreeId = UUID()

        store.consume(
            makeFilesystemEnvelope(
                seq: 5,
                worktreeId: worktreeId,
                event: .branchChanged(
                    worktreeId: worktreeId,
                    repoId: worktreeId,
                    from: "main",
                    to: "feature/new"
                )
            )
        )
        store.consume(
            makeFilesystemEnvelope(
                seq: 4,
                worktreeId: worktreeId,
                event: .gitSnapshotChanged(
                    snapshot: GitWorkingTreeSnapshot(
                        worktreeId: worktreeId,
                        rootPath: URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)"),
                        summary: GitWorkingTreeSummary(changed: 9, staged: 9, untracked: 9),
                        branch: "feature/new"
                    )
                )
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
        let store = WorkspaceGitWorkingTreeStore()
        let keepWorktreeId = UUID()
        let dropWorktreeId = UUID()

        store.consume(
            makeFilesystemEnvelope(
                seq: 1,
                worktreeId: keepWorktreeId,
                event: .gitSnapshotChanged(
                    snapshot: GitWorkingTreeSnapshot(
                        worktreeId: keepWorktreeId,
                        rootPath: URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)"),
                        summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                        branch: "main"
                    )
                )
            )
        )
        store.consume(
            makeFilesystemEnvelope(
                seq: 2,
                worktreeId: dropWorktreeId,
                event: .gitSnapshotChanged(
                    snapshot: GitWorkingTreeSnapshot(
                        worktreeId: dropWorktreeId,
                        rootPath: URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)"),
                        summary: GitWorkingTreeSummary(changed: 0, staged: 1, untracked: 0),
                        branch: "feature/drop"
                    )
                )
            )
        )

        store.prune(validWorktreeIds: Set([keepWorktreeId]))

        #expect(store.snapshotsByWorktreeId[keepWorktreeId] != nil)
        #expect(store.snapshotsByWorktreeId[dropWorktreeId] == nil)
    }

    @Test("reset clears all materialized snapshots")
    func resetClearsAllSnapshots() {
        let store = WorkspaceGitWorkingTreeStore()
        let worktreeId = UUID()

        store.consume(
            makeFilesystemEnvelope(
                seq: 1,
                worktreeId: worktreeId,
                event: .gitSnapshotChanged(
                    snapshot: GitWorkingTreeSnapshot(
                        worktreeId: worktreeId,
                        rootPath: URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)"),
                        summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                        branch: "main"
                    )
                )
            )
        )
        #expect(store.snapshotsByWorktreeId[worktreeId] != nil)

        store.reset()
        #expect(store.snapshotsByWorktreeId.isEmpty)
    }

    @Test("filesChanged compatibility maps to worktree filesystem namespace and is ignored by git snapshot store")
    func filesChangedCompatibilityMappingIsIgnoredByStore() {
        let store = WorkspaceGitWorkingTreeStore()
        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)")
        let filesystemEvent = FilesystemEvent.filesChanged(
            changeset: FileChangeset(
                worktreeId: worktreeId,
                rootPath: rootPath,
                paths: ["Sources/OnlyFilesystem.swift"],
                timestamp: ContinuousClock().now,
                batchSeq: 1
            )
        )

        #expect(filesystemEvent.compatibilityScope == .worktreeFilesystem)
        guard case .filesystem(.filesChanged)? = filesystemEvent.compatibilityWorktreeScopedEvent else {
            Issue.record("Expected filesChanged compatibility worktree mapping")
            return
        }

        store.consume(
            makeFilesystemEnvelope(
                seq: 1,
                worktreeId: worktreeId,
                event: filesystemEvent
            )
        )

        #expect(store.snapshotsByWorktreeId[worktreeId] == nil)
    }

    @Test("git snapshot and branch compatibility map to git working directory namespace")
    func gitSnapshotAndBranchCompatibilityMapping() {
        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)")
        let snapshotEvent = FilesystemEvent.gitSnapshotChanged(
            snapshot: GitWorkingTreeSnapshot(
                worktreeId: worktreeId,
                rootPath: rootPath,
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "main"
            )
        )
        let branchEvent = FilesystemEvent.branchChanged(
            worktreeId: worktreeId,
            repoId: worktreeId,
            from: "main",
            to: "feature/mapped"
        )

        #expect(snapshotEvent.compatibilityScope == .worktreeGitWorkingDirectory)
        #expect(branchEvent.compatibilityScope == .worktreeGitWorkingDirectory)

        guard case .gitWorkingDirectory(.snapshotChanged(let mappedSnapshot))? = snapshotEvent.compatibilityWorktreeScopedEvent else {
            Issue.record("Expected gitSnapshotChanged compatibility mapping")
            return
        }
        #expect(mappedSnapshot.worktreeId == worktreeId)
        #expect(mappedSnapshot.branch == "main")

        guard
            case .gitWorkingDirectory(.branchChanged(let mappedWorktreeId, let mappedRepoId, let from, let to))? =
            branchEvent.compatibilityWorktreeScopedEvent
        else {
            Issue.record("Expected branchChanged compatibility mapping")
            return
        }
        #expect(mappedWorktreeId == worktreeId)
        #expect(mappedRepoId == worktreeId)
        #expect(from == "main")
        #expect(to == "feature/mapped")
    }

    private func makeFilesystemEnvelope(
        seq: UInt64,
        worktreeId: UUID,
        event: FilesystemEvent
    ) -> PaneEventEnvelope {
        PaneEventEnvelope(
            source: .system(.builtin(.filesystemWatcher)),
            sourceFacets: PaneContextFacets(repoId: worktreeId, worktreeId: worktreeId),
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
