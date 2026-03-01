import Foundation
import Observation
import os

@Observable
@MainActor
final class WorkspaceGitWorkingTreeStore {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "WorkspaceGitWorkingTreeStore")

    struct WorktreeSnapshot: Sendable, Equatable {
        let worktreeId: UUID
        let repoId: UUID
        let summary: GitWorkingTreeSummary
        let branch: String?
        let lastSequence: UInt64
        let timestamp: ContinuousClock.Instant
    }

    private(set) var snapshotsByWorktreeId: [UUID: WorktreeSnapshot] = [:]

    func consume(_ envelope: PaneEventEnvelope) {
        guard case .filesystem(let filesystemEvent) = envelope.event else { return }
        guard let worktreeId = resolveWorktreeId(envelope: envelope, filesystemEvent: filesystemEvent) else {
            return
        }
        let existingSnapshot = snapshotsByWorktreeId[worktreeId]
        let repoId =
            resolveRepoId(envelope: envelope, filesystemEvent: filesystemEvent)
            ?? existingSnapshot?.repoId
            ?? worktreeId

        let baselineSnapshot =
            existingSnapshot
            ?? WorktreeSnapshot(
                worktreeId: worktreeId,
                repoId: repoId,
                summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                branch: nil,
                lastSequence: 0,
                timestamp: envelope.timestamp
            )
        // Sequence ordering is per GitWorkingDirectoryProjector producer stream.
        // This store only materializes `.gitSnapshotChanged`/`.branchChanged`, so
        // cross-producer sequence comparisons do not apply here.
        guard envelope.seq >= baselineSnapshot.lastSequence else { return }
        if baselineSnapshot.lastSequence > 0, envelope.seq > baselineSnapshot.lastSequence + 1 {
            Self.logger.warning(
                "Detected git working-tree event gap for worktree \(worktreeId.uuidString, privacy: .public): last=\(baselineSnapshot.lastSequence, privacy: .public), next=\(envelope.seq, privacy: .public)"
            )
        }

        let nextSummary: GitWorkingTreeSummary
        let nextBranch: String?
        switch filesystemEvent {
        case .gitSnapshotChanged(let gitSnapshot):
            nextSummary = gitSnapshot.summary
            nextBranch = gitSnapshot.branch
        case .branchChanged(_, _, _, let branchName):
            nextSummary = baselineSnapshot.summary
            nextBranch = branchName
        case .worktreeRegistered, .worktreeUnregistered, .filesChanged, .diffAvailable:
            return
        }

        snapshotsByWorktreeId[worktreeId] = WorktreeSnapshot(
            worktreeId: worktreeId,
            repoId: repoId,
            summary: nextSummary,
            branch: nextBranch,
            lastSequence: envelope.seq,
            timestamp: envelope.timestamp
        )
    }

    func prune(validWorktreeIds: Set<UUID>) {
        snapshotsByWorktreeId = snapshotsByWorktreeId.filter { validWorktreeIds.contains($0.key) }
    }

    func reset() {
        snapshotsByWorktreeId.removeAll()
    }

    private func resolveWorktreeId(
        envelope: PaneEventEnvelope,
        filesystemEvent: FilesystemEvent
    ) -> UUID? {
        if let worktreeId = envelope.sourceFacets.worktreeId {
            return worktreeId
        }
        switch filesystemEvent {
        case .worktreeRegistered(let worktreeId, _, _):
            return worktreeId
        case .worktreeUnregistered(let worktreeId, _):
            return worktreeId
        case .filesChanged(let changeset):
            return changeset.worktreeId
        case .gitSnapshotChanged(let snapshot):
            return snapshot.worktreeId
        case .diffAvailable(_, let worktreeId, _):
            return worktreeId
        case .branchChanged(let worktreeId, _, _, _):
            return worktreeId
        }
    }

    private func resolveRepoId(
        envelope: PaneEventEnvelope,
        filesystemEvent: FilesystemEvent
    ) -> UUID? {
        if let repoId = envelope.sourceFacets.repoId {
            return repoId
        }
        switch filesystemEvent {
        case .worktreeRegistered(_, let repoId, _):
            return repoId
        case .worktreeUnregistered(_, let repoId):
            return repoId
        case .filesChanged(let changeset):
            return changeset.repoId
        case .gitSnapshotChanged(let snapshot):
            return snapshot.repoId
        case .diffAvailable(_, _, let repoId):
            return repoId
        case .branchChanged(_, let repoId, _, _):
            return repoId
        }
    }
}
