import Foundation

package struct GitBranchStatus: Equatable, Sendable {
    package enum SyncState: Equatable, Sendable {
        case synced
        case ahead(Int)
        case behind(Int)
        case diverged(ahead: Int, behind: Int)
        case noUpstream
        case unknown
    }

    package let isDirty: Bool
    package let syncState: SyncState
    package let prCount: Int?
    /// True when this branch's repository has a resolved, terminal absence
    /// of pull request data (no GitHub remote, or provider queries have
    /// failed past the forge honesty threshold). Distinguishes "we haven't
    /// heard back yet" (`prCount == nil` alone) from "no data is coming",
    /// so consumers stop rendering a pending indicator for the latter.
    package let pullRequestDataUnavailable: Bool
    package let linesAdded: Int
    package let linesDeleted: Int
    package let untrackedFileCount: Int

    package static let unknown = Self(
        isDirty: false,
        syncState: .unknown,
        prCount: nil,
        pullRequestDataUnavailable: false,
        linesAdded: 0,
        linesDeleted: 0,
        untrackedFileCount: 0
    )

    package init(
        isDirty: Bool,
        syncState: SyncState,
        prCount: Int?,
        pullRequestDataUnavailable: Bool = false,
        linesAdded: Int,
        linesDeleted: Int,
        untrackedFileCount: Int
    ) {
        self.isDirty = isDirty
        self.syncState = syncState
        self.prCount = prCount
        self.pullRequestDataUnavailable = pullRequestDataUnavailable
        self.linesAdded = linesAdded
        self.linesDeleted = linesDeleted
        self.untrackedFileCount = untrackedFileCount
    }

    package static func merge(
        worktreeEnrichmentsByWorktreeId: [UUID: WorktreeEnrichment],
        pullRequestFactsByBranch: [RepoBranchKey: PullRequestFacts],
        unavailablePullRequestRepoIds: Set<UUID> = []
    ) -> [UUID: Self] {
        var mergedByWorktreeId: [UUID: Self] = [:]
        mergedByWorktreeId.reserveCapacity(worktreeEnrichmentsByWorktreeId.count)

        for (worktreeId, enrichment) in worktreeEnrichmentsByWorktreeId {
            let pullRequestFacts = RepoBranchKey(repoId: enrichment.repoId, branch: enrichment.branch)
                .flatMap { pullRequestFactsByBranch[$0] }
            mergedByWorktreeId[worktreeId] = status(
                enrichment: enrichment,
                pullRequestFacts: pullRequestFacts,
                pullRequestDataUnavailable: unavailablePullRequestRepoIds.contains(enrichment.repoId)
            )
        }

        return mergedByWorktreeId
    }

    package static func status(
        enrichment: WorktreeEnrichment?,
        pullRequestFacts: PullRequestFacts?,
        pullRequestDataUnavailable: Bool = false
    ) -> Self {
        guard let enrichment else {
            return Self(
                isDirty: Self.unknown.isDirty,
                syncState: Self.unknown.syncState,
                prCount: pullRequestFacts?.openCount,
                pullRequestDataUnavailable: pullRequestDataUnavailable,
                linesAdded: Self.unknown.linesAdded,
                linesDeleted: Self.unknown.linesDeleted,
                untrackedFileCount: Self.unknown.untrackedFileCount
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
            prCount: pullRequestFacts?.openCount,
            pullRequestDataUnavailable: pullRequestDataUnavailable,
            linesAdded: summary?.linesAdded ?? 0,
            linesDeleted: summary?.linesDeleted ?? 0,
            untrackedFileCount: summary?.untracked ?? 0
        )
    }
}
