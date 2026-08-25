import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation typed hydration")
struct WorktreeAnnotationTypedHydrationTests {
    @Test("repository hydrates exact human and agent attention state")
    func repositoryHydratesExactAuthorAttentionState() throws {
        let fixture = try makeSavedHydrationFixture()

        try fixture.databaseQueue.write { database in
            try database.execute(
                sql: "UPDATE annotation_message SET author_kind = 'agent' WHERE id = ?",
                arguments: [fixture.messageID.databaseValue]
            )
        }
        let unseenAgent = try #require(
            fixture.repository.fetchSessionDetail(sessionID: fixture.sessionID).threads.first?.messages.first
        )
        #expect(unseenAgent.authorKind == .agent)
        #expect(unseenAgent.viewedSavedRevision == nil)
        #expect(try unseenAgent.projectNewPendingState().attentionState == .new)

        try fixture.databaseQueue.write { database in
            try database.execute(
                sql: "UPDATE annotation_message SET viewed_saved_revision = 1 WHERE id = ?",
                arguments: [fixture.messageID.databaseValue]
            )
        }
        let viewedAgent = try #require(
            fixture.repository.fetchSessionDetail(sessionID: fixture.sessionID).threads.first?.messages.first
        )
        #expect(viewedAgent.authorKind == .agent)
        #expect(viewedAgent.viewedSavedRevision == 1)
        #expect(try viewedAgent.projectNewPendingState().attentionState == .viewed)
    }

    @Test(
        "repository rejects invalid stored author attention combinations",
        arguments: InvalidStoredAuthorState.allCases
    )
    func repositoryRejectsInvalidStoredAuthorAttentionCombination(
        mutation: InvalidStoredAuthorState
    ) throws {
        let fixture = try makeSavedHydrationFixture()
        try fixture.databaseQueue.write { database in
            try mutation.apply(database: database, messageID: fixture.messageID)
        }

        #expect(throws: WorktreeAnnotationRepositoryError.invalidState) {
            try fixture.repository.fetchSessionDetail(sessionID: fixture.sessionID)
        }
    }

    @Test("repository rejects an agent message with a working draft")
    func repositoryRejectsAgentWorkingDraft() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let repository = WorktreeAnnotationSQLiteRepository(databaseWriter: databaseQueue)
        let detail = try repository.createRootDraft(makeLocatedRootDraftProps())
        let message = try #require(detail.threads.first?.messages.first)
        try databaseQueue.write { database in
            try database.execute(
                sql: "UPDATE annotation_message SET author_kind = 'agent' WHERE id = ?",
                arguments: [message.id.databaseValue]
            )
        }

        #expect(throws: WorktreeAnnotationRepositoryError.invalidState) {
            try repository.fetchSessionDetail(sessionID: detail.session.id)
        }
    }

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

enum InvalidStoredAuthorState: CaseIterable, Sendable {
    case humanViewed
    case agentHandled
    case agentViewedNewerThanCurrent
    case unknownAuthor

    func apply(database: Database, messageID: WorktreeAnnotationMessageID) throws {
        let sql: String =
            switch self {
            case .humanViewed:
                "UPDATE annotation_message SET author_kind = 'human', viewed_saved_revision = 1 WHERE id = ?"
            case .agentHandled:
                "UPDATE annotation_message SET author_kind = 'agent', handled = 1 WHERE id = ?"
            case .agentViewedNewerThanCurrent:
                "UPDATE annotation_message SET author_kind = 'agent', viewed_saved_revision = 2 WHERE id = ?"
            case .unknownAuthor:
                "UPDATE annotation_message SET author_kind = 'future_author' WHERE id = ?"
            }
        try database.execute(sql: sql, arguments: [messageID.databaseValue])
    }
}

private struct SavedHydrationFixture {
    let databaseQueue: DatabaseQueue
    let repository: WorktreeAnnotationSQLiteRepository
    let sessionID: WorktreeAnnotationSessionID
    let messageID: WorktreeAnnotationMessageID
}

private func makeSavedHydrationFixture() throws -> SavedHydrationFixture {
    let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
    try WorkspaceLocalMigrations.migrate(databaseQueue)
    let repository = WorktreeAnnotationSQLiteRepository(databaseWriter: databaseQueue)
    let draftDetail = try repository.createRootDraft(makeLocatedRootDraftProps())
    let draftMessage = try #require(draftDetail.threads.first?.messages.first)
    let savedDetail = try repository.saveDraft(
        .init(
            sessionID: draftDetail.session.id,
            messageID: draftMessage.id,
            editToken: "editor-1",
            expectedMessageRevision: draftMessage.semanticRevision,
            expectedDraftRevision: 0,
            now: Date(timeIntervalSince1970: 3)
        )
    )
    let savedMessage = try #require(savedDetail.threads.first?.messages.first)
    return SavedHydrationFixture(
        databaseQueue: databaseQueue,
        repository: repository,
        sessionID: savedDetail.session.id,
        messageID: savedMessage.id
    )
}
