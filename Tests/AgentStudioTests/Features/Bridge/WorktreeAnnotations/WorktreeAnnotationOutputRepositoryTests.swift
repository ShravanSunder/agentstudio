import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation output repository")
struct WorktreeAnnotationOutputRepositoryTests {
    @Test("prepare persists strict canonical semantics, exact bytes, and ordered membership")
    func preparePersistsCanonicalSemanticsAndExactMaterialization() throws {
        let fixture = try makeOutputRepositoryFixture()

        let prepared = try fixture.repository.prepareOutput(fixture.prepareProps())

        #expect(prepared.canonicalSnapshot == fixture.snapshot)
        #expect(prepared.attempt.exactBytes == fixture.exactBytes)
        #expect(
            prepared.memberships == [
                .init(
                    messageID: fixture.message.id,
                    expectedSavedRevision: fixture.savedRevision,
                    batchOrdinal: 0
                )
            ]
        )
        let storedSnapshotJSON = try fixture.databaseQueue.read { database in
            try String.fetchOne(
                database,
                sql: "SELECT snapshot_json FROM annotation_output_attempt WHERE id = ?",
                arguments: [fixture.attemptID.rawValue.uuidString]
            )
        }
        #expect(storedSnapshotJSON.map { Data($0.utf8) } == fixture.snapshotJSON)
    }

    @Test("inspection fails closed when persisted canonical semantics are malformed")
    func inspectionFailsClosedForMalformedCanonicalSemantics() throws {
        let fixture = try makeOutputRepositoryFixture()
        _ = try fixture.repository.prepareOutput(fixture.prepareProps())
        try fixture.databaseQueue.write { database in
            try database.execute(
                sql: "UPDATE annotation_output_attempt SET snapshot_json = ? WHERE id = ?",
                arguments: ["{\"formatVersion\":1,\"unexpected\":true}", fixture.attemptID.rawValue.uuidString]
            )
        }

        #expect(throws: (any Error).self) {
            try fixture.repository.inspectOutputAttempt(attemptID: fixture.attemptID)
        }
    }

    @Test("prepare rejects a snapshot whose durable message semantics do not match SQLite")
    func prepareRejectsSnapshotWithFabricatedDurableSemantics() throws {
        let fixture = try makeOutputRepositoryFixture()
        let persistedEntry = try #require(fixture.snapshot.entries.first)
        let fabricatedEntry = WorktreeAnnotationBatchSnapshot.Entry(
            batchOrdinal: persistedEntry.batchOrdinal,
            thread: .init(
                threadID: persistedEntry.threadID,
                resolution: .resolved,
                origin: persistedEntry.origin,
                placement: persistedEntry.placement
            ),
            message: .init(
                messageID: persistedEntry.messageID,
                messageOrdinal: persistedEntry.messageOrdinal,
                savedRevision: persistedEntry.savedRevision,
                bodyMarkdown: "Fabricated output body"
            )
        )
        let fabricatedSnapshot = WorktreeAnnotationBatchSnapshot(
            batchID: fixture.snapshot.batchID,
            createdAt: fixture.snapshot.createdAt,
            session: fixture.snapshot.session,
            entries: [fabricatedEntry]
        )

        #expect(throws: WorktreeAnnotationRepositoryError.invalidState) {
            try fixture.repository.prepareOutput(
                fixture.prepareProps(
                    canonicalSnapshot: fabricatedSnapshot,
                    exactBytes: WorktreeAnnotationBatchProjector.markdownData(
                        for: fabricatedSnapshot,
                        presentation: outputRepositoryMarkdownPresentation
                    )
                )
            )
        }
    }

    @Test("one session admits only one prepared output attempt at a time")
    func prepareRejectsSecondInFlightAttemptForSession() throws {
        let fixture = try makeOutputRepositoryFixture()
        _ = try fixture.repository.prepareOutput(fixture.prepareProps())
        let threadID = try #require(fixture.detail.threads.first?.thread.id)
        var detailWithReply = try fixture.repository.createReplyDraft(
            .init(
                sessionID: fixture.detail.session.id,
                threadID: threadID,
                expectedThreadRevision: try #require(fixture.detail.threads.first?.thread.semanticRevision),
                body: "A distinct reply for the next output",
                editToken: "reply-editor",
                now: Date(timeIntervalSince1970: 4)
            )
        )
        let replyDraft = try #require(detailWithReply.threads.first?.messages.last)
        detailWithReply = try fixture.repository.saveDraft(
            .init(
                sessionID: detailWithReply.session.id,
                messageID: replyDraft.id,
                editToken: "reply-editor",
                expectedMessageRevision: replyDraft.semanticRevision,
                expectedDraftRevision: 0,
                now: Date(timeIntervalSince1970: 5)
            )
        )
        let reply = try #require(detailWithReply.threads.first?.messages.last)
        let replySavedRevision = try #require(reply.savedRevision)
        let nextAttemptID = WorktreeAnnotationOutputAttemptID(rawValue: testUUID(72))
        let nextSnapshot = try WorktreeAnnotationBatchProjector.makeSnapshot(
            .init(
                batchID: nextAttemptID,
                createdAt: Date(timeIntervalSince1970: 6),
                sessionDetail: detailWithReply,
                selectedMessages: [
                    .init(messageID: reply.id, expectedSavedRevision: replySavedRevision)
                ],
                placementsByThreadID: outputRepositoryPlacements(detailWithReply),
                sessionLabel: "Current review",
                worktreeLabel: "agent-studio.review-comments",
                comparisonLabel: nil
            )
        )

        #expect(throws: WorktreeAnnotationRepositoryError.invalidState) {
            try fixture.repository.prepareOutput(
                .init(
                    attemptID: nextAttemptID,
                    sessionID: detailWithReply.session.id,
                    outputKind: .clipboardMarkdown,
                    formatVersion: nextSnapshot.formatVersion,
                    contentType: "text/markdown; charset=utf-8",
                    canonicalSnapshot: nextSnapshot,
                    exactBytes: WorktreeAnnotationBatchProjector.markdownData(
                        for: nextSnapshot,
                        presentation: outputRepositoryMarkdownPresentation
                    ),
                    markdownPresentation: outputRepositoryMarkdownPresentation,
                    destinationPath: nil,
                    repeatedFromAttemptID: nil,
                    selectedMessages: [
                        .init(messageID: reply.id, expectedSavedRevision: replySavedRevision)
                    ],
                    now: Date(timeIntervalSince1970: 6)
                )
            )
        }
    }

    @Test("finalization rejects an event kind that contradicts the prepared output kind")
    func finalizationRejectsMismatchedEventKind() throws {
        let fixture = try makeOutputRepositoryFixture()
        let prepared = try fixture.repository.prepareOutput(fixture.prepareProps())

        #expect(throws: WorktreeAnnotationRepositoryError.invalidState) {
            try fixture.repository.finalizeOutputAttempt(
                attemptID: prepared.attempt.id,
                eventKind: .exported,
                now: Date(timeIntervalSince1970: 4)
            )
        }
    }

    @Test("explicit repetition reuses persisted bytes and membership after message locking")
    func explicitRepetitionReusesPersistedAttemptWithoutRebuilding() throws {
        let fixture = try makeOutputRepositoryFixture()
        let prepared = try fixture.repository.prepareOutput(fixture.prepareProps())
        let succeeded = try fixture.repository.finalizeOutputAttempt(
            attemptID: prepared.attempt.id,
            eventKind: .copied,
            now: Date(timeIntervalSince1970: 4)
        )
        let repeatedAttemptID = WorktreeAnnotationOutputAttemptID(rawValue: testUUID(72))

        let repeated = try fixture.repository.repeatOutputAttempt(
            sourceAttemptID: succeeded.attempt.id,
            repeatedAttemptID: repeatedAttemptID,
            destinationPath: nil,
            now: Date(timeIntervalSince1970: 5)
        )

        #expect(repeated.attempt.id == repeatedAttemptID)
        #expect(repeated.attempt.repeatedFromAttemptID == succeeded.attempt.id)
        #expect(repeated.attempt.exactBytes == fixture.exactBytes)
        #expect(repeated.canonicalSnapshot == fixture.snapshot)
        #expect(repeated.memberships == succeeded.memberships)
        #expect(
            try fixture.repository.fetchSessionDetail(sessionID: fixture.detail.session.id)
                .threads.first?.thread.resolution == .open
        )
    }

    @Test("history is bounded, newest first, and excludes cancelled attempts")
    func historyIsBoundedAndExcludesCancelledAttempts() throws {
        let fixture = try makeOutputRepositoryFixture()
        let cancelled = try fixture.repository.prepareOutput(fixture.prepareProps())
        _ = try fixture.repository.cancelOutputAttempt(
            attemptID: cancelled.attempt.id,
            effectError: "clipboard unavailable",
            now: Date(timeIntervalSince1970: 4)
        )

        let succeededAttemptID = WorktreeAnnotationOutputAttemptID(rawValue: testUUID(73))
        let succeeded = try fixture.repository.prepareOutput(
            fixture.prepareProps(attemptID: succeededAttemptID, now: Date(timeIntervalSince1970: 5))
        )
        _ = try fixture.repository.finalizeOutputAttempt(
            attemptID: succeeded.attempt.id,
            eventKind: .copied,
            now: Date(timeIntervalSince1970: 6)
        )
        let repeated = try fixture.repository.repeatOutputAttempt(
            sourceAttemptID: succeeded.attempt.id,
            repeatedAttemptID: .init(rawValue: testUUID(74)),
            destinationPath: nil,
            now: Date(timeIntervalSince1970: 7)
        )
        #expect(try fixture.repository.markPreparedOutputAttemptsUnknown(now: Date(timeIntervalSince1970: 8)) == 1)

        let history = try fixture.repository.fetchOutputHistory(
            sessionID: fixture.detail.session.id,
            limit: 1
        )

        #expect(history.count == 1)
        #expect(history.first?.attemptID == repeated.attempt.id)
        #expect(history.first?.state == .unknown)
        #expect(history.first?.messageCount == 1)
        #expect(history.first?.canMarkNotHandled == false)
        #expect(history.first?.attemptID != cancelled.attempt.id)
    }

    @Test("finalization failure locks exact membership without handling or an output event")
    func finalizationFailureLocksWithoutHandling() throws {
        let fixture = try makeOutputRepositoryFixture()
        let prepared = try fixture.repository.prepareOutput(fixture.prepareProps())

        let failed = try fixture.repository.markOutputAttemptFinalizationFailed(
            attemptID: prepared.attempt.id,
            cleanupError: "forced finalization failure",
            now: Date(timeIntervalSince1970: 4)
        )

        let message = try #require(
            fixture.repository.fetchSessionDetail(sessionID: fixture.detail.session.id)
                .threads.first?.messages.first
        )
        #expect(failed.attempt.state == .finalizationFailed)
        #expect(failed.event == nil)
        #expect(message.status == .locked)
        #expect(message.handled == false)
        #expect(
            try fixture.repository.fetchOutputHistory(sessionID: fixture.detail.session.id, limit: 10)
                .first?.canMarkNotHandled == false
        )
    }

    @Test("unknown recovery locks exact membership without handling or replay evidence")
    func unknownRecoveryLocksWithoutHandling() throws {
        let fixture = try makeOutputRepositoryFixture()
        let prepared = try fixture.repository.prepareOutput(fixture.prepareProps())

        #expect(
            try fixture.repository.markPreparedOutputAttemptsUnknown(
                now: Date(timeIntervalSince1970: 4)
            ) == 1
        )
        #expect(
            try fixture.repository.markPreparedOutputAttemptsUnknown(
                now: Date(timeIntervalSince1970: 5)
            ) == 0
        )

        let recovered = try fixture.repository.inspectOutputAttempt(attemptID: prepared.attempt.id)
        let message = try #require(
            fixture.repository.fetchSessionDetail(sessionID: fixture.detail.session.id)
                .threads.first?.messages.first
        )
        #expect(recovered.attempt.state == .unknown)
        #expect(recovered.event == nil)
        #expect(message.status == .locked)
        #expect(message.handled == false)
        #expect(
            try fixture.repository.fetchOutputHistory(sessionID: fixture.detail.session.id, limit: 10)
                .first?.canMarkNotHandled == false
        )
    }

}

private struct OutputRepositoryFixture {
    let databaseQueue: DatabaseQueue
    let repository: WorktreeAnnotationSQLiteRepository
    let detail: WorktreeAnnotationSessionDetail
    let message: WorktreeAnnotationMessage
    let savedRevision: Int
    let attemptID: WorktreeAnnotationOutputAttemptID
    let snapshot: WorktreeAnnotationBatchSnapshot
    let snapshotJSON: Data
    let exactBytes: Data

    func prepareProps(
        attemptID: WorktreeAnnotationOutputAttemptID? = nil,
        now: Date = Date(timeIntervalSince1970: 3),
        canonicalSnapshot: WorktreeAnnotationBatchSnapshot? = nil,
        exactBytes: Data? = nil
    ) throws -> WorktreeAnnotationSQLiteRepository.PrepareOutputProps {
        let selectedAttemptID = attemptID ?? self.attemptID
        let selectedSnapshot =
            try canonicalSnapshot
            ?? WorktreeAnnotationBatchProjector.makeSnapshot(
                .init(
                    batchID: selectedAttemptID,
                    createdAt: now,
                    sessionDetail: detail,
                    selectedMessages: [
                        .init(messageID: message.id, expectedSavedRevision: savedRevision)
                    ],
                    placementsByThreadID: outputRepositoryPlacements(detail),
                    sessionLabel: "Current review",
                    worktreeLabel: "agent-studio.review-comments",
                    comparisonLabel: nil
                )
            )
        return .init(
            attemptID: selectedAttemptID,
            sessionID: detail.session.id,
            outputKind: .clipboardMarkdown,
            formatVersion: WorktreeAnnotationBatchSnapshot.currentFormatVersion,
            contentType: "text/markdown; charset=utf-8",
            canonicalSnapshot: selectedSnapshot,
            exactBytes: exactBytes
                ?? WorktreeAnnotationBatchProjector.markdownData(
                    for: selectedSnapshot,
                    presentation: outputRepositoryMarkdownPresentation
                ),
            markdownPresentation: outputRepositoryMarkdownPresentation,
            destinationPath: nil,
            repeatedFromAttemptID: nil,
            selectedMessages: [
                .init(messageID: message.id, expectedSavedRevision: savedRevision)
            ],
            now: now
        )
    }
}

private func makeOutputRepositoryFixture() throws -> OutputRepositoryFixture {
    let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
    try WorkspaceLocalMigrations.migrate(databaseQueue)
    let repository = WorktreeAnnotationSQLiteRepository(databaseWriter: databaseQueue)
    var detail = try repository.createRootDraft(
        .init(
            admission: .implicitOrSingle,
            repositoryID: "repository-1",
            worktreeID: "worktree-1",
            originatingWorkspaceID: "workspace-1",
            sourceFingerprint: .init(
                repositoryID: "repository-1",
                worktreeID: "worktree-1",
                fileSourceIdentity: "source-1",
                reviewComparisonOrigin: nil
            ),
            origin: .located(
                .init(
                    repositoryRelativePath: "Sources/Feature.swift",
                    startLine: 1,
                    endLine: 1,
                    sourceRole: .file,
                    diffSide: nil,
                    sourceIdentity: "source-1",
                    selectedExcerpt: "let value = 1",
                    contextBefore: nil,
                    contextAfter: nil
                )
            ),
            body: "Keep this behavior",
            editToken: "editor-1",
            now: Date(timeIntervalSince1970: 1)
        )
    )
    let draftMessage = try #require(detail.threads.first?.messages.first)
    detail = try repository.saveDraft(
        .init(
            sessionID: detail.session.id,
            messageID: draftMessage.id,
            editToken: "editor-1",
            expectedMessageRevision: draftMessage.semanticRevision,
            expectedDraftRevision: 0,
            now: Date(timeIntervalSince1970: 2)
        )
    )
    let message = try #require(detail.threads.first?.messages.first)
    let savedRevision = try #require(message.savedRevision)
    let attemptID = WorktreeAnnotationOutputAttemptID(rawValue: testUUID(71))
    let snapshot = try WorktreeAnnotationBatchProjector.makeSnapshot(
        .init(
            batchID: attemptID,
            createdAt: Date(timeIntervalSince1970: 3),
            sessionDetail: detail,
            selectedMessages: [
                .init(messageID: message.id, expectedSavedRevision: savedRevision)
            ],
            placementsByThreadID: outputRepositoryPlacements(detail),
            sessionLabel: "Current review",
            worktreeLabel: "agent-studio.review-comments",
            comparisonLabel: nil
        )
    )
    return try OutputRepositoryFixture(
        databaseQueue: databaseQueue,
        repository: repository,
        detail: detail,
        message: message,
        savedRevision: savedRevision,
        attemptID: attemptID,
        snapshot: snapshot,
        snapshotJSON: WorktreeAnnotationBatchProjector.jsonData(for: snapshot),
        exactBytes: WorktreeAnnotationBatchProjector.markdownData(
            for: snapshot,
            presentation: outputRepositoryMarkdownPresentation
        )
    )
}

private let outputRepositoryMarkdownPresentation = WorktreeAnnotationMarkdownPresentationContext(
    worktreeLabel: "agent-studio.review-comments",
    comparisonLabel: nil
)

private func outputRepositoryPlacements(
    _ detail: WorktreeAnnotationSessionDetail
) -> [WorktreeAnnotationThreadID: WorktreeAnnotationThreadPlacementProjection] {
    Dictionary(
        uniqueKeysWithValues: detail.threads.map { threadDetail in
            (
                threadDetail.thread.id,
                .init(
                    placement: .exact,
                    currentPath: "Sources/Feature.swift",
                    currentStartLine: 1,
                    currentEndLine: 1,
                    currentSourceIdentity: "source-1"
                )
            )
        }
    )
}

private func testUUID(_ suffix: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-7000-8000-%012d", suffix))!
}
