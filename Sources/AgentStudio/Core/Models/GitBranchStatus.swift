import Foundation

struct GitBranchStatus: Equatable, Sendable {
    enum SyncState: Equatable, Sendable {
        case synced
        case ahead(Int)
        case behind(Int)
        case diverged(ahead: Int, behind: Int)
        case noUpstream
        case unknown
    }

    let isDirty: Bool
    let syncState: SyncState
    let prCount: Int?
    let linesAdded: Int
    let linesDeleted: Int

    static let unknown = Self(isDirty: false, syncState: .unknown, prCount: nil, linesAdded: 0, linesDeleted: 0)

    static func merge(
        worktreeEnrichmentsByWorktreeId: [UUID: WorktreeEnrichment],
        pullRequestCountsByWorktreeId: [UUID: Int]
    ) -> [UUID: Self] {
        let allWorktreeIds = Set(worktreeEnrichmentsByWorktreeId.keys).union(pullRequestCountsByWorktreeId.keys)
        var mergedByWorktreeId: [UUID: Self] = [:]
        mergedByWorktreeId.reserveCapacity(allWorktreeIds.count)

        for worktreeId in allWorktreeIds {
            mergedByWorktreeId[worktreeId] = status(
                enrichment: worktreeEnrichmentsByWorktreeId[worktreeId],
                pullRequestCount: pullRequestCountsByWorktreeId[worktreeId]
            )
        }

        return mergedByWorktreeId
    }

    static func status(
        enrichment: WorktreeEnrichment?,
        pullRequestCount: Int?
    ) -> Self {
        guard let enrichment else {
            return Self(
                isDirty: Self.unknown.isDirty,
                syncState: Self.unknown.syncState,
                prCount: pullRequestCount,
                linesAdded: Self.unknown.linesAdded,
                linesDeleted: Self.unknown.linesDeleted
            )
        }

        let summary = enrichment.snapshot?.summary
        let isDirty: Bool
        if let summary {
            isDirty = summary.changed > 0 || summary.staged > 0 || summary.untracked > 0
        } else {
            isDirty = false
        }

        let syncState: Self.SyncState
        if let summary {
            switch summary.hasUpstream {
            case .some(false):
                syncState = .noUpstream
            case .some(true):
                let ahead = summary.aheadCount ?? 0
                let behind = summary.behindCount ?? 0
                if ahead > 0 && behind > 0 {
                    syncState = .diverged(ahead: ahead, behind: behind)
                } else if ahead > 0 {
                    syncState = .ahead(ahead)
                } else if behind > 0 {
                    syncState = .behind(behind)
                } else if summary.aheadCount != nil || summary.behindCount != nil {
                    syncState = .synced
                } else {
                    syncState = .unknown
                }
            case .none:
                syncState = .unknown
            }
        } else {
            syncState = .unknown
        }

        return Self(
            isDirty: isDirty,
            syncState: syncState,
            prCount: pullRequestCount,
            linesAdded: summary?.linesAdded ?? 0,
            linesDeleted: summary?.linesDeleted ?? 0
        )
    }
}
