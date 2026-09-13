import Foundation

extension WorkspaceMutationCoordinator {
    package func captureRepositoryLifecycleInput() -> RepositoryLifecycleInput {
        RepositoryLifecycleInput(
            revision: repositoryTopologyAtom.lifecycleRevision,
            membershipRevision: repositoryTopologyAtom.worktreePathIndexGeneration,
            repositories: repositoryTopologyAtom.repos,
            watchedPaths: repositoryTopologyAtom.watchedPaths,
            absenceRecords: repositoryTopologyAtom.absenceRecords,
            stableIdentity: RepositoryTopologyStableIdentity(
                repositoryStableKeysByID: repositoryTopologyAtom.repositoryStableKeysByID,
                worktreeStableKeysByID: repositoryTopologyAtom.worktreeStableKeysByID,
                watchedPathStableKeysByID: repositoryTopologyAtom.watchedPathStableKeysByID
            )
        )
    }

    @discardableResult
    package func applyRepositoryLifecycleChange(_ change: RepositoryLifecycleChange) -> Bool {
        guard repositoryTopologyAtom.lifecycleRevision == change.expectedRevision else { return false }
        repositoryTopologyAtom.replaceTopology(change.replacement)
        return true
    }

    /// Time is captured at the source off MainActor. Repeated absence never resets it.
    @discardableResult
    package func recordRepositoryAbsence(
        _ repositoryID: UUID,
        at time: RepositoryRetentionTime
    ) -> Bool {
        guard let repository = repositoryTopologyAtom.repo(repositoryID) else { return false }
        var records = repositoryTopologyAtom.absenceRecords
        guard
            let absence = RepositoryRetentionPolicy.confirmedAbsence(
                retaining: records.repositories[repositoryID], at: time
            )
        else { return false }
        records.repositories[repositoryID] = absence
        for worktree in repository.worktrees {
            guard
                let worktreeAbsence = RepositoryRetentionPolicy.confirmedAbsence(
                    retaining: records.worktrees[worktree.id], at: time
                )
            else { return false }
            records.worktrees[worktree.id] = worktreeAbsence
        }
        return applyAbsenceRecords(records)
    }

    @discardableResult
    package func recordWorktreeAbsence(
        _ worktreeID: UUID,
        at time: RepositoryRetentionTime
    ) -> Bool {
        guard let worktree = repositoryTopologyAtom.worktree(worktreeID),
            let repository = repositoryTopologyAtom.repo(worktree.repoId)
        else { return false }
        var records = repositoryTopologyAtom.absenceRecords
        guard
            let absence = RepositoryRetentionPolicy.confirmedAbsence(
                retaining: records.worktrees[worktreeID], at: time
            )
        else { return false }
        records.worktrees[worktreeID] = absence
        if repository.worktrees.allSatisfy({ records.worktrees[$0.id] != nil }) {
            guard
                let repositoryAbsence = RepositoryRetentionPolicy.confirmedAbsence(
                    retaining: records.repositories[repository.id], at: time
                )
            else { return false }
            records.repositories[repository.id] = repositoryAbsence
        }
        return applyAbsenceRecords(records)
    }

    @discardableResult
    package func restoreObservedWorktrees(_ worktreeIDs: Set<UUID>) -> Bool {
        var records = repositoryTopologyAtom.absenceRecords
        for worktreeID in worktreeIDs {
            guard let worktree = repositoryTopologyAtom.worktree(worktreeID) else { continue }
            records.worktrees.removeValue(forKey: worktreeID)
            records.repositories.removeValue(forKey: worktree.repoId)
        }
        return applyAbsenceRecords(records)
    }

    private func applyAbsenceRecords(_ records: RepositoryTopologyAbsenceRecords) -> Bool {
        guard records != repositoryTopologyAtom.absenceRecords else { return false }
        switch RepositoryTopologyReplacement.prepare(
            repositories: repositoryTopologyAtom.repos,
            watchedPaths: repositoryTopologyAtom.watchedPaths,
            unavailableRepositoryIDs: records.unavailableRepositoryIDs,
            stableIdentity: RepositoryTopologyStableIdentity(
                repositoryStableKeysByID: repositoryTopologyAtom.repositoryStableKeysByID,
                worktreeStableKeysByID: repositoryTopologyAtom.worktreeStableKeysByID,
                watchedPathStableKeysByID: repositoryTopologyAtom.watchedPathStableKeysByID
            ),
            absenceRecords: records
        ) {
        case .prepared(let replacement):
            repositoryTopologyAtom.replaceTopology(replacement)
            return true
        case .rejected:
            return false
        }
    }
}
