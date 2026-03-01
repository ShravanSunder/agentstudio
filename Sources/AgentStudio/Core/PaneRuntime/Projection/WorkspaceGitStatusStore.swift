import Foundation
import Observation

@Observable
@MainActor
final class WorkspaceGitStatusStore {
    struct WorktreeSnapshot: Sendable, Equatable {
        let worktreeId: UUID
        let summary: GitStatusSummary
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

        let existingSnapshot =
            snapshotsByWorktreeId[worktreeId]
            ?? WorktreeSnapshot(
                worktreeId: worktreeId,
                summary: GitStatusSummary(changed: 0, staged: 0, untracked: 0),
                branch: nil,
                lastSequence: 0,
                timestamp: envelope.timestamp
            )
        guard envelope.seq >= existingSnapshot.lastSequence else { return }

        let nextSummary: GitStatusSummary
        let nextBranch: String?
        switch filesystemEvent {
        case .gitSnapshotChanged(let gitSnapshot):
            nextSummary = gitSnapshot.summary
            nextBranch = gitSnapshot.branch
        case .branchChanged(_, let branchName):
            nextSummary = existingSnapshot.summary
            nextBranch = branchName
        case .worktreeRegistered, .worktreeUnregistered, .filesChanged, .diffAvailable:
            return
        }

        snapshotsByWorktreeId[worktreeId] = WorktreeSnapshot(
            worktreeId: worktreeId,
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
        case .worktreeRegistered(let worktreeId, _):
            return worktreeId
        case .worktreeUnregistered(let worktreeId):
            return worktreeId
        case .filesChanged(let changeset):
            return changeset.worktreeId
        case .gitSnapshotChanged(let snapshot):
            return snapshot.worktreeId
        case .diffAvailable, .branchChanged:
            return nil
        }
    }
}
