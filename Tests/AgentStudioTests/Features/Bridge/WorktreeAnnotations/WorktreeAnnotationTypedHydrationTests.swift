import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation typed hydration")
struct WorktreeAnnotationTypedHydrationTests {
    @Test("repository rejects an unknown stored thread scope")
    func repositoryRejectsUnknownStoredThreadScope() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let repository = WorktreeAnnotationSQLiteRepository(databaseWriter: databaseQueue)
        let detail = try repository.createRootDraft(makeLocatedRootDraftProps())
        let threadID = try #require(detail.threads.first?.thread.id)

        try databaseQueue.write { database in
            try database.execute(
                sql: "UPDATE annotation_thread SET scope = 'future_scope' WHERE id = ?",
                arguments: [threadID.databaseValue]
            )
        }

        #expect(throws: WorktreeAnnotationRepositoryError.invalidState) {
            try repository.fetchSessionDetail(sessionID: detail.session.id)
        }
    }

    @Test("repository rejects a stored thread scope that disagrees with its origin")
    func repositoryRejectsStoredThreadScopeOriginMismatch() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let repository = WorktreeAnnotationSQLiteRepository(databaseWriter: databaseQueue)
        let detail = try repository.createRootDraft(makeLocatedRootDraftProps())
        let threadID = try #require(detail.threads.first?.thread.id)

        try databaseQueue.write { database in
            try database.execute(
                sql: "UPDATE annotation_thread SET scope = 'session' WHERE id = ?",
                arguments: [threadID.databaseValue]
            )
        }

        #expect(throws: WorktreeAnnotationRepositoryError.invalidState) {
            try repository.fetchSessionDetail(sessionID: detail.session.id)
        }
    }

    @Test("repository rejects an unknown stored recovery kind")
    func repositoryRejectsUnknownStoredRecoveryKind() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let repository = WorktreeAnnotationSQLiteRepository(databaseWriter: databaseQueue)
        let provenanceID = WorktreeAnnotationRecoveryProvenanceID.generate()

        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO local_recovery_provenance(
                        id, recovery_kind, recovered_at, quarantined_filenames_json,
                        reason, acknowledged_at
                    ) VALUES (?, 'future_recovery', 1, '[]', 'test', NULL)
                    """,
                arguments: [provenanceID.databaseValue]
            )
        }

        #expect(throws: WorktreeAnnotationRepositoryError.invalidState) {
            try repository.fetchUnacknowledgedRecoveryProvenance()
        }
    }
}
