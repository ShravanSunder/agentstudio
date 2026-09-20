import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioSessions

@Suite("Sessions repository")
struct SessionsRepositoryTests {
    @Test("message text is exact and only its explicit occurrence acknowledgment changes seen state")
    func exactMessageAndOccurrenceAcknowledgment() async throws {
        let fixture = try SessionsDatabaseFixture()
        try await withSessionsIngestion(repository: fixture.makeRepository()) { ingestion in
            let paneId = UUIDv7.generate()
            let sourceGenerationId = UUIDv7.generate()
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId,
                        providerConversationId: "conversation-message",
                        sourceGenerationId: sourceGenerationId,
                        reportedAt: 1
                    )
                )
            )
            let exactText = "Private first line\n第二行 with emoji 🛰️\n"
            let firstMessageOutcome = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .message(
                    SessionsMessageMutation(
                        context: .currentPaneBinding(paneId: paneId),
                        text: exactText,
                        freshness: .live,
                        receivedAt: Date(timeIntervalSince1970: 2)
                    )
                )
            )
            let secondMessageOutcome = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .message(
                    SessionsMessageMutation(
                        context: .currentPaneBinding(paneId: paneId),
                        text: "Unrelated message",
                        freshness: .live,
                        receivedAt: Date(timeIntervalSince1970: 3)
                    )
                )
            )
            guard case .messageSaved(let firstOccurrenceId, .attributed) = firstMessageOutcome,
                case .messageSaved(let secondOccurrenceId, .attributed) = secondMessageOutcome
            else {
                throw SessionsTestError.unexpectedOutcome("Expected two attributed messages")
            }

            let readSnapshot = try await ingestion.snapshot(
                makeSessionsSnapshotQuery(paneId: paneId)
            )
            let firstReadMessage = try #require(
                readSnapshot.messages.first { $0.occurrenceId == firstOccurrenceId }
            )
            #expect(firstReadMessage.text == exactText)
            #expect(firstReadMessage.disposition == .unseen)
            #expect(readSnapshot.currentAttention.isEmpty)

            let acknowledgment = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .acknowledgeMessage(
                    SessionsMessageAcknowledgmentMutation(
                        occurrenceId: firstOccurrenceId,
                        acknowledgedAt: Date(timeIntervalSince1970: 4)
                    )
                )
            )
            #expect(acknowledgment == .messageAcknowledged(occurrenceId: firstOccurrenceId, changed: true))
            let repeatedAcknowledgment = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .acknowledgeMessage(
                    SessionsMessageAcknowledgmentMutation(
                        occurrenceId: firstOccurrenceId,
                        acknowledgedAt: Date(timeIntervalSince1970: 5)
                    )
                )
            )
            #expect(
                repeatedAcknowledgment
                    == .messageAcknowledged(occurrenceId: firstOccurrenceId, changed: false)
            )

            let acknowledgedSnapshot = try await ingestion.snapshot(
                makeSessionsSnapshotQuery(paneId: paneId)
            )
            #expect(
                acknowledgedSnapshot.messages.first { $0.occurrenceId == firstOccurrenceId }?.disposition
                    == .seen
            )
            #expect(
                acknowledgedSnapshot.messages.first { $0.occurrenceId == secondOccurrenceId }?.disposition
                    == .unseen
            )
            #expect(acknowledgedSnapshot.currentAttention.isEmpty)
        }
    }

    @Test("equivalent correlation replay is one occurrence and conflicting reuse changes nothing")
    func correlationDeduplicationAndConflict() async throws {
        let fixture = try SessionsDatabaseFixture()
        try await withSessionsIngestion(repository: fixture.makeRepository()) { ingestion in
            let paneId = UUIDv7.generate()
            let correlationId = UUIDv7.generate()
            let messageMutation = SessionsMutation.message(
                SessionsMessageMutation(
                    context: .unattributed(paneId: paneId),
                    text: "same content",
                    freshness: .late,
                    receivedAt: Date(timeIntervalSince1970: 1)
                )
            )

            let firstOutcome = try await ingestion.submit(
                correlationId: correlationId,
                mutation: messageMutation
            )
            let replayOutcome = try await ingestion.submit(
                correlationId: correlationId,
                mutation: messageMutation
            )

            #expect(replayOutcome == firstOutcome)
            guard case .messageSaved(let occurrenceId, .unattributed) = firstOutcome else {
                throw SessionsTestError.unexpectedOutcome("Expected unattributed message")
            }
            let snapshotBeforeConflict = try await ingestion.snapshot(makeUnattributedSessionsSnapshotQuery())
            #expect(snapshotBeforeConflict.messages.map(\.occurrenceId) == [occurrenceId])
            await #expect(throws: SessionsRepositoryError.correlationConflict(correlationId)) {
                try await ingestion.submit(
                    correlationId: correlationId,
                    mutation: .message(
                        SessionsMessageMutation(
                            context: .unattributed(paneId: paneId),
                            text: "different content",
                            freshness: .late,
                            receivedAt: Date(timeIntervalSince1970: 20)
                        )
                    )
                )
            }
            let snapshotAfterConflict = try await ingestion.snapshot(makeUnattributedSessionsSnapshotQuery())
            #expect(snapshotAfterConflict == snapshotBeforeConflict)
        }
    }

    @Test("domain and operation writes roll back together")
    func domainAndOperationWritesRollBackTogether() async throws {
        let fixture = try SessionsDatabaseFixture()
        let correlationId = UUIDv7.generate()
        try await fixture.sqliteAccess.write { database in
            try database.execute(
                sql: """
                    CREATE TRIGGER reject_sessions_message
                    BEFORE INSERT ON sessions_message
                    WHEN NEW.exact_text = 'force rollback'
                    BEGIN
                        SELECT RAISE(ABORT, 'forced sessions rollback');
                    END
                    """
            )
        }

        try await withSessionsIngestion(repository: fixture.makeRepository()) { ingestion in
            await #expect(throws: DatabaseError.self) {
                try await ingestion.submit(
                    correlationId: correlationId,
                    mutation: .message(
                        SessionsMessageMutation(
                            context: .unattributed(paneId: UUIDv7.generate()),
                            text: "force rollback",
                            freshness: .late,
                            receivedAt: Date(timeIntervalSince1970: 1)
                        )
                    )
                )
            }

            let retainedRowCounts = try await fixture.sqliteAccess.read { database in
                (
                    operation: try Int.fetchOne(
                        database,
                        sql: "SELECT COUNT(*) FROM sessions_operation WHERE correlation_id = ?",
                        arguments: [correlationId.uuidString]
                    ) ?? -1,
                    message: try Int.fetchOne(
                        database,
                        sql: "SELECT COUNT(*) FROM sessions_message WHERE exact_text = 'force rollback'"
                    ) ?? -1
                )
            }
            #expect(retainedRowCounts.operation == 0)
            #expect(retainedRowCounts.message == 0)
        }
    }

    @Test("late unattributed messages remain queryable after database reopen")
    func lateUnattributedMessageSurvivesReopen() async throws {
        let fixture = try SessionsFileDatabaseFixture()
        defer { fixture.removeFiles() }
        let paneId = UUIDv7.generate()
        let exactText = "offline text\nkept exactly"
        let occurrenceId = try await withSessionsIngestion(
            repository: fixture.makeRepository()
        ) { ingestion in
            let outcome = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .message(
                    SessionsMessageMutation(
                        context: .unattributed(paneId: paneId),
                        text: exactText,
                        freshness: .late,
                        receivedAt: Date(timeIntervalSince1970: 1)
                    )
                )
            )
            guard case .messageSaved(let occurrenceId, .unattributed) = outcome else {
                throw SessionsTestError.unexpectedOutcome("Expected late unattributed message")
            }
            return occurrenceId
        }

        try await withSessionsIngestion(repository: fixture.makeRepository()) { ingestion in
            let reopenedSnapshot = try await ingestion.snapshot(makeUnattributedSessionsSnapshotQuery())
            let message = try #require(
                reopenedSnapshot.messages.first { $0.occurrenceId == occurrenceId }
            )
            #expect(message.paneId == paneId)
            #expect(message.conversationId == nil)
            #expect(message.attribution == .unattributed)
            #expect(message.freshness == .late)
            #expect(message.text == exactText)
            #expect(message.disposition == .unseen)
        }
    }
}
