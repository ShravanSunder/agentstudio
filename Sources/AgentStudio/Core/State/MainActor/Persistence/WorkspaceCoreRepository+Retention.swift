import AgentStudioInfrastructure
import Foundation
import GRDB

extension WorkspaceCoreRepository {
    /// Caller supplies freshly validated scope admission. This transaction independently checks durable age and ownership.
    func collectRetainedRepositoryLocations(
        _ candidates: RepositoryRetentionCandidates,
        at time: RepositoryRetentionTime
    ) throws -> RepositoryTopologyRecord {
        guard candidates.count <= AppPolicies.RepositoryRetention.collectionBatchLimit else {
            throw RepositoryRetentionCollectionError.batchLimitExceeded
        }
        return try databaseWriter.write { database in
            let topology = try readRepositoryTopology(database)
            try validateRetentionCandidates(candidates, topology: topology, at: time)
            for worktreeID in candidates.worktreeAbsences.keys {
                try database.execute(sql: "DELETE FROM worktree WHERE id = ?", arguments: [worktreeID.uuidString])
            }
            for repositoryID in candidates.repositoryAbsences.keys {
                try database.execute(sql: "DELETE FROM repo WHERE id = ?", arguments: [repositoryID.uuidString])
            }
            try clearInvalidPaneTopologyFacets(database)
            return try readRepositoryTopology(database)
        }
    }
}

private func validateRetentionCandidates(
    _ candidates: RepositoryRetentionCandidates,
    topology: WorkspaceCoreRepository.RepositoryTopologyRecord,
    at time: RepositoryRetentionTime
) throws {
    let repositories = Dictionary(uniqueKeysWithValues: topology.repos.map { ($0.id, $0) })
    let worktrees = Dictionary(uniqueKeysWithValues: topology.repos.flatMap(\.worktrees).map { ($0.id, $0) })
    for (worktreeID, expected) in candidates.worktreeAbsences {
        guard worktrees[worktreeID] != nil else { continue }
        guard topology.absenceRecords.worktrees[worktreeID] == expected,
            RepositoryRetentionPolicy.isDue(expected, at: time)
        else { throw RepositoryRetentionCollectionError.noLongerEligible }
    }
    for (repositoryID, expected) in candidates.repositoryAbsences {
        guard let repository = repositories[repositoryID] else { continue }
        guard topology.absenceRecords.repositories[repositoryID] == expected,
            RepositoryRetentionPolicy.isDue(expected, at: time),
            repository.worktrees.allSatisfy({ candidates.worktreeAbsences[$0.id] != nil })
        else { throw RepositoryRetentionCollectionError.noLongerEligible }
    }
}
