import Foundation

extension GitWorkingDirectoryProjector {
    struct MaterializedGitStatus: Sendable {
        let result: GitWorkingTreeStatusResult
        let facts: GitWorkingTreeStatusFacts
        let detail: GitWorkingTreeLineDetail?
        let refreshedDetail: Bool
    }

    func materializeCompleteStatus(
        facts: GitWorkingTreeStatusFacts,
        changeset: FileChangeset
    ) async -> MaterializedGitStatus {
        let worktreeId = changeset.worktreeId
        let acceptedFacts = lastAcceptedStatusFactsByWorktreeId[worktreeId]
        let acceptedDetail = lastAcceptedLineDetailByWorktreeId[worktreeId]
        let detailIsFresh =
            lastAcceptedLineDetailAtByWorktreeId[worktreeId].map {
                $0.duration(to: envelopeClock.now) < refreshPolicy.lineDetailFreshnessInterval
            } ?? false
        // Synthetic registration/attention refreshes intentionally carry an
        // empty path set even when their changeset is marked Git-internal.
        // They refresh facts, but do not prove that worktree content changed.
        let contentWasInvalidated = !changeset.paths.isEmpty
        let isExplicit = refreshAttribution.admittedDemandClassByWorktreeId[worktreeId] == "explicit"
        let needsDetail =
            acceptedDetail == nil
            || acceptedFacts != facts
            || contentWasInvalidated
            || isExplicit
            || !detailIsFresh

        if !needsDetail, let acceptedDetail {
            return MaterializedGitStatus(
                result: .available(facts.composing(acceptedDetail)),
                facts: facts,
                detail: acceptedDetail,
                refreshedDetail: false
            )
        }

        switch await gitWorkingTreeProvider.lineDetailResult(for: changeset.rootPath) {
        case .available(let detail):
            return MaterializedGitStatus(
                result: .available(facts.composing(detail)),
                facts: facts,
                detail: detail,
                refreshedDetail: true
            )
        case .unavailable(let unavailable):
            return MaterializedGitStatus(
                result: .unavailable(unavailable),
                facts: facts,
                detail: nil,
                refreshedDetail: false
            )
        }
    }
}
