import Foundation
import GRDB
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("Repository retention rollback")
struct RepositoryRetentionRollbackTests {
    enum Rejection: CaseIterable, Sendable { case changedAbsence, transactionFailure }

    @Test("failed collection preserves the complete durable topology", arguments: Rejection.allCases)
    func failedCollectionRollsBack(_ rejection: Rejection) throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let root = URL(fileURLWithPath: "/tmp/retention-rollback")
        let start = RepositoryRetentionTime(
            utc: Date(timeIntervalSince1970: 1_700_000_000), bootID: "fixture", uptimeNanoseconds: 1)
        let absence = try #require(RepositoryRetentionPolicy.confirmedAbsence(retaining: nil, at: start))
        let candidates = RepositoryRetentionCandidates(
            repositoryAbsences: [repositoryID: absence], worktreeAbsences: [worktreeID: absence])
        let currentAbsence: RepositoryLocationAbsence = rejection == .changedAbsence ? .unconfirmed : absence
        let topology = WorkspaceCoreRepository.RepositoryTopologyRecord(
            watchedPaths: [],
            repos: [
                .init(
                    id: repositoryID, name: "retained", repoPath: root,
                    createdAt: start.utc, isPinned: true, note: "keep until commit",
                    worktrees: [
                        .init(
                            id: worktreeID, repoId: repositoryID, name: "main", path: root, isMainWorktree: true,
                            note: "checkout note")
                    ], tags: ["retained"])
            ],
            unavailableRepoIds: [repositoryID],
            absenceRecords: .init(repositories: [repositoryID: currentAbsence], worktrees: [worktreeID: currentAbsence])
        )
        try fixture.repository.replaceRepositoryTopology(topology)
        if rejection == .transactionFailure {
            try fixture.databaseQueue.write { database in
                try database.execute(
                    sql:
                        "CREATE TRIGGER fail_retention_commit BEFORE DELETE ON repo BEGIN SELECT RAISE(ABORT, 'retention fixture commit failure'); END"
                )
            }
        }
        let due = RepositoryRetentionTime(
            utc: start.utc, bootID: start.bootID,
            uptimeNanoseconds: start.uptimeNanoseconds + 30 * 86_400 * 1_000_000_000)

        do {
            _ = try fixture.repository.collectRetainedRepositoryLocations(candidates, at: due)
            Issue.record("expected collection rejection")
        } catch {
            if rejection == .changedAbsence {
                #expect(error as? RepositoryRetentionCollectionError == .noLongerEligible)
            } else {
                #expect(error is DatabaseError)
            }
        }

        #expect(try fixture.repository.fetchRepositoryTopology() == topology)
        let violations = try fixture.databaseQueue.read { database in
            try Row.fetchAll(database, sql: "PRAGMA foreign_key_check")
        }
        #expect(violations.isEmpty)
    }
}
