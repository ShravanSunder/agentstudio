import Foundation
import Observation

@Observable
@MainActor
final class WorkspaceGitStatusStore {
    struct WorktreeSnapshot: Sendable {
        let worktreeId: UUID
        var summary: GitStatusSummary
        var branch: String?
        var lastSequence: UInt64
        var timestamp: ContinuousClock.Instant
    }

    static let shared = WorkspaceGitStatusStore()

    private(set) var snapshotsByWorktreeId: [UUID: WorktreeSnapshot] = [:]

    func consume(_ envelope: PaneEventEnvelope) {
        guard case .filesystem(let filesystemEvent) = envelope.event else { return }
        guard let worktreeId = resolveWorktreeId(envelope: envelope, filesystemEvent: filesystemEvent) else {
            return
        }

        var snapshot =
            snapshotsByWorktreeId[worktreeId]
            ?? WorktreeSnapshot(
                worktreeId: worktreeId,
                summary: GitStatusSummary(changed: 0, staged: 0, untracked: 0),
                branch: nil,
                lastSequence: 0,
                timestamp: envelope.timestamp
            )
        guard envelope.seq >= snapshot.lastSequence else { return }

        switch filesystemEvent {
        case .gitSnapshotChanged(let gitSnapshot):
            snapshot.summary = gitSnapshot.summary
            snapshot.branch = gitSnapshot.branch
        case .branchChanged(_, let nextBranch):
            snapshot.branch = nextBranch
        case .worktreeRegistered, .worktreeUnregistered, .filesChanged, .diffAvailable:
            return
        }

        snapshot.lastSequence = envelope.seq
        snapshot.timestamp = envelope.timestamp
        snapshotsByWorktreeId[worktreeId] = snapshot
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
