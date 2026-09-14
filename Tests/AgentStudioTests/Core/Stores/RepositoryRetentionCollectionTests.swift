import Foundation
import GRDB
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("Repository retention collection")
struct RepositoryRetentionCollectionTests {
    @Test("collection removes only due hidden topology and preserves an available sibling")
    func collectionKeepsAvailableSiblingAndRejectsEarlyExpiry() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repository = fixture.repository
        let repoID = UUIDv7.generate()
        let mainID = UUIDv7.generate()
        let linkedID = UUIDv7.generate()
        let path = URL(fileURLWithPath: "/tmp/collection-main")
        let start = RepositoryRetentionTime(
            utc: Date(timeIntervalSince1970: 1_700_000_000), bootID: "fixture", uptimeNanoseconds: 1)
        let absence = try #require(RepositoryRetentionPolicy.confirmedAbsence(retaining: nil, at: start))
        let topology = WorkspaceCoreRepository.RepositoryTopologyRecord(
            watchedPaths: [],
            repos: [
                .init(
                    id: repoID, name: "family", repoPath: path,
                    createdAt: start.utc, isPinned: true, note: "family survives",
                    worktrees: [
                        .init(
                            id: mainID, repoId: repoID, name: "main", path: path, isMainWorktree: true, note: "expired"),
                        .init(
                            id: linkedID, repoId: repoID, name: "linked",
                            path: URL(fileURLWithPath: "/tmp/collection-linked"), isMainWorktree: false, note: "keep"),
                    ], tags: ["keep"])
            ],
            unavailableRepoIds: [],
            absenceRecords: .init(worktrees: [mainID: absence])
        )
        try repository.replaceRepositoryTopology(topology)
        let sessionID = UUIDv7.generate().uuidString
        let closeID = UUIDv7.generate().uuidString
        try fixture.databaseQueue.write { database in
            try database.execute(
                sql: "INSERT INTO workspace_terminal_session_ownership(session_id) VALUES (?)", arguments: [sessionID])
            try database.execute(
                sql: """
                    INSERT INTO workspace_undo_close(
                        close_id, workspace_id, close_sequence, close_kind, closed_at, expires_at,
                        state, snapshot_version, snapshot_payload, deadline_boot_id, deadline_uptime_ns
                    ) VALUES (?, ?, 1, 'pane', 100, 400, 'available', 1, ?, 'fixture', 400000000000)
                    """,
                arguments: [
                    closeID, UUIDv7.generate().uuidString,
                    Data("{\"repoId\":\"\(repoID)\",\"worktreeId\":\"\(mainID)\"}".utf8),
                ])
            try database.execute(
                sql: "INSERT INTO workspace_undo_close_member(close_id, pane_id, session_id) VALUES (?, ?, ?)",
                arguments: [closeID, UUIDv7.generate().uuidString, sessionID])
        }
        let protectedTables = [
            "workspace_terminal_session_ownership", "workspace_undo_close", "workspace_undo_close_member",
        ]
        let protectedBefore = try fixture.databaseQueue.read { database in
            try protectedTables.map { table in
                try Row.fetchAll(database, sql: "SELECT * FROM \(table) ORDER BY rowid")
                    .map { Array($0.databaseValues) }
            }
        }
        let candidates = RepositoryRetentionCandidates(repositoryAbsences: [:], worktreeAbsences: [mainID: absence])
        let early = RepositoryRetentionTime(
            utc: start.utc, bootID: start.bootID, uptimeNanoseconds: start.uptimeNanoseconds + 1)
        #expect(throws: RepositoryRetentionCollectionError.noLongerEligible) {
            try repository.collectRetainedRepositoryLocations(candidates, at: early)
        }
        #expect(try repository.fetchRepositoryTopology() == topology)
        let due = RepositoryRetentionTime(
            utc: start.utc, bootID: start.bootID,
            uptimeNanoseconds: start.uptimeNanoseconds + 30 * 86_400 * 1_000_000_000)

        let result = try repository.collectRetainedRepositoryLocations(candidates, at: due)

        #expect(result.repos.count == 1)
        #expect(result.repos[0].id == repoID)
        #expect(result.repos[0].worktrees.map(\.id) == [linkedID])
        #expect(result.repos[0].worktrees[0].note == "keep")
        #expect(result.repos[0].note == "family survives")
        #expect(result.repos[0].tags == ["keep"])
        #expect(result.repos[0].isPinned)
        #expect(result.absenceRecords.worktrees.isEmpty)
        let protectedAfter = try fixture.databaseQueue.read { database in
            try protectedTables.map { table in
                try Row.fetchAll(database, sql: "SELECT * FROM \(table) ORDER BY rowid")
                    .map { Array($0.databaseValues) }
            }
        }
        #expect(protectedAfter == protectedBefore)
    }
}
