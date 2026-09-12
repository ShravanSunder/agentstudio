import Foundation

package struct RepositoryRetentionCandidates: Equatable, Sendable {
    package let repositoryAbsences: [UUID: RepositoryLocationAbsence]
    package let worktreeAbsences: [UUID: RepositoryLocationAbsence]

    package var isEmpty: Bool { repositoryAbsences.isEmpty && worktreeAbsences.isEmpty }
    package var count: Int { repositoryAbsences.count + worktreeAbsences.count }

    package init(
        repositoryAbsences: [UUID: RepositoryLocationAbsence], worktreeAbsences: [UUID: RepositoryLocationAbsence]
    ) {
        self.repositoryAbsences = repositoryAbsences
        self.worktreeAbsences = worktreeAbsences
    }
}

package enum RepositoryRetentionCollectionError: Error, Equatable {
    case noLongerEligible
    case batchLimitExceeded
    case staleTopology
}
