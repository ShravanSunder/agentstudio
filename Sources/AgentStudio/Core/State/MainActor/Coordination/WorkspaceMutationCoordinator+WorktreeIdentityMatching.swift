import AgentStudioInfrastructure
import Foundation

extension WorkspaceMutationCoordinator {
    func matchCandidatesPreservingExistingWorktreeIdentity(
        repositoryID: UUID,
        candidates: [WorktreeReconciliationCandidate],
        existingWorktrees: [Worktree]
    ) -> MatchedCandidateWorktrees {
        let existingByPath = Dictionary(
            existingWorktrees.map { ($0.path.standardizedFileURL, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var consumedExistingIDs = Set<UUID>()
        var preservedWorktreeIDs: [UUID] = []
        var stableKeysByID: [UUID: String] = [:]

        let worktrees = candidates.map { candidate -> Worktree in
            let matchedWorktree: Worktree?
            if let pathMatch = existingByPath[candidate.path.standardizedFileURL],
                !consumedExistingIDs.contains(pathMatch.id)
            {
                matchedWorktree = pathMatch
            } else {
                matchedWorktree = nil
            }

            if let matchedWorktree {
                consumedExistingIDs.insert(matchedWorktree.id)
                preservedWorktreeIDs.append(matchedWorktree.id)
                let updatedWorktree = Worktree(
                    id: matchedWorktree.id,
                    repoId: repositoryID,
                    name: candidate.name,
                    path: candidate.path,
                    isMainWorktree: candidate.isMainWorktree,
                    note: matchedWorktree.note
                )
                stableKeysByID[updatedWorktree.id] = candidate.stableKey
                return updatedWorktree
            }
            let unmatchedWorktree = candidate.makeUnmatchedWorktree(repositoryID: repositoryID)
            stableKeysByID[unmatchedWorktree.id] = candidate.stableKey
            return unmatchedWorktree
        }
        return MatchedCandidateWorktrees(
            worktrees: worktrees,
            preservedWorktreeIDs: preservedWorktreeIDs,
            stableKeysByID: stableKeysByID
        )
    }

}

enum WorktreeReconciliationCandidate {
    case scannedMain(RepositoryScannedMainWorktree)
    case scannedLinked(RepositoryScannedLinkedWorktree)
    case identified(Worktree)

    var name: String {
        switch self {
        case .scannedMain(let candidate): candidate.name
        case .scannedLinked(let candidate): candidate.name
        case .identified(let worktree): worktree.name
        }
    }

    var path: URL {
        switch self {
        case .scannedMain(let candidate): candidate.path
        case .scannedLinked(let candidate): candidate.path
        case .identified(let worktree): worktree.path
        }
    }

    var isMainWorktree: Bool {
        switch self {
        case .scannedMain: true
        case .scannedLinked: false
        case .identified(let worktree): worktree.isMainWorktree
        }
    }

    var stableKey: String {
        switch self {
        case .scannedMain(let candidate): candidate.stableKey
        case .scannedLinked(let candidate): candidate.stableKey
        case .identified(let worktree): worktree.stableKey
        }
    }

    func makeUnmatchedWorktree(repositoryID: UUID) -> Worktree {
        switch self {
        case .scannedMain(let candidate):
            Worktree(
                id: UUIDv7.generate(),
                repoId: repositoryID,
                name: candidate.name,
                path: candidate.path,
                isMainWorktree: true
            )
        case .scannedLinked(let candidate):
            Worktree(
                id: UUIDv7.generate(),
                repoId: repositoryID,
                name: candidate.name,
                path: candidate.path,
                isMainWorktree: false
            )
        case .identified(let worktree):
            worktree
        }
    }
}

struct PreparedWorktreeReconciliation {
    let repositoryIndex: Int
    let mergedWorktrees: [Worktree]
    let worktreeStableKeysByID: [UUID: String]
    let hasValidMainWorktree: Bool
    let delta: WorktreeTopologyDelta
}

struct MatchedCandidateWorktrees {
    let worktrees: [Worktree]
    let preservedWorktreeIDs: [UUID]
    let stableKeysByID: [UUID: String]
}

enum WorktreeReconciliationPreparation {
    case prepared(PreparedWorktreeReconciliation)
    case rejected(RepositoryWorktreeReconciliationRejection)
}
