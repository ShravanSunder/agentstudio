import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation viewed mutation")
struct WorktreeAnnotationViewedMutationTests {
    @Test("two exact agent revisions change atomically and advance the session once")
    func twoExactAgentRevisionsAdvanceSessionOnce() throws {
        let fixture = try makeViewedMutationFixture()
        let initialSessionRevision = fixture.detail.session.semanticRevision
        let initialMessageRevisions = fixture.agentMessages.map(\.semanticRevision)
        let duplicateItem = WorktreeAnnotationSQLiteRepository.ViewedItem(
            messageID: fixture.agentMessages[0].id,
            expectedSavedRevision: try #require(fixture.agentMessages[0].savedRevision)
        )

        #expect(throws: WorktreeAnnotationRepositoryError.invalidState) {
            try fixture.repository.markMessagesViewed(
                .init(
                    sessionID: fixture.detail.session.id,
                    items: [duplicateItem, duplicateItem],
                    now: Date(timeIntervalSince1970: 19)
                )
            )
        }

        let result = try fixture.repository.markMessagesViewed(
            .init(
                sessionID: fixture.detail.session.id,
                items: fixture.agentMessages.map {
                    .init(messageID: $0.id, expectedSavedRevision: try #require($0.savedRevision))
                },
                now: Date(timeIntervalSince1970: 20)
            )
        )

        #expect(result.changed)
        #expect(result.sessionID == fixture.detail.session.id)
        #expect(result.results.count == 2)
        #expect(
            result.results.allSatisfy { result in
                guard case .viewed(_, _, let committedSessionRevision, .changed) = result else {
                    return false
                }
                return committedSessionRevision == initialSessionRevision + 1
            })
        let persisted = try fixture.repository.fetchSessionDetail(sessionID: fixture.detail.session.id)
        #expect(persisted.session.semanticRevision == initialSessionRevision + 1)
        #expect(persisted.threads.first?.messages.map(\.semanticRevision) == initialMessageRevisions.map { $0 + 1 })
        #expect(
            try persisted.threads.first?.messages.map { try $0.projectNewPendingState().attentionState }
                == [.viewed, .viewed]
        )
    }

    @Test("mixed viewed evaluation preserves request order and does not leak another session")
    func mixedEvaluationPreservesOrderAndSessionBoundary() throws {
        let fixture = try makeViewedMutationFixture()
        let firstAgent = fixture.agentMessages[0]
        let secondAgent = fixture.agentMessages[1]
        let firstSavedRevision = try #require(firstAgent.savedRevision)
        let secondSavedRevision = try #require(secondAgent.savedRevision)
        let detailWithHumanMessage = try addSavedMessage(
            repository: fixture.repository,
            detail: fixture.detail,
            body: "Human reply",
            editToken: "human-reply",
            now: 10
        )
        let humanMessage = try #require(detailWithHumanMessage.threads.first?.messages.last)
        let otherSession = try addSavedRootSession(
            repository: fixture.repository,
            body: "Other session",
            editToken: "other-session",
            now: 12
        )
        let otherMessage = try #require(otherSession.threads.first?.messages.first)
        let missingMessageID = WorktreeAnnotationMessageID.generate()

        let result = try fixture.repository.markMessagesViewed(
            .init(
                sessionID: fixture.detail.session.id,
                items: [
                    .init(messageID: firstAgent.id, expectedSavedRevision: firstSavedRevision),
                    .init(messageID: secondAgent.id, expectedSavedRevision: secondSavedRevision + 1),
                    .init(
                        messageID: humanMessage.id,
                        expectedSavedRevision: try #require(humanMessage.savedRevision)
                    ),
                    .init(
                        messageID: otherMessage.id,
                        expectedSavedRevision: try #require(otherMessage.savedRevision)
                    ),
                    .init(messageID: missingMessageID, expectedSavedRevision: 1),
                ],
                now: Date(timeIntervalSince1970: 20)
            )
        )

        #expect(
            result.results == [
                .viewed(
                    messageID: firstAgent.id,
                    savedRevision: firstSavedRevision,
                    committedSessionRevision: detailWithHumanMessage.session.semanticRevision + 1,
                    disposition: .changed
                ),
                .notViewed(
                    messageID: secondAgent.id,
                    expectedSavedRevision: secondSavedRevision + 1,
                    disposition: .stale
                ),
                .notViewed(
                    messageID: humanMessage.id,
                    expectedSavedRevision: try #require(humanMessage.savedRevision),
                    disposition: .notAgent
                ),
                .notViewed(
                    messageID: otherMessage.id,
                    expectedSavedRevision: try #require(otherMessage.savedRevision),
                    disposition: .notFound
                ),
                .notViewed(
                    messageID: missingMessageID,
                    expectedSavedRevision: 1,
                    disposition: .notFound
                ),
            ])

        let repeated = try fixture.repository.markMessagesViewed(
            .init(
                sessionID: fixture.detail.session.id,
                items: [
                    .init(messageID: firstAgent.id, expectedSavedRevision: firstSavedRevision)
                ],
                now: Date(timeIntervalSince1970: 21)
            )
        )
        #expect(!repeated.changed)
        #expect(
            repeated.results == [
                .viewed(
                    messageID: firstAgent.id,
                    savedRevision: firstSavedRevision,
                    committedSessionRevision: detailWithHumanMessage.session.semanticRevision + 1,
                    disposition: .alreadyViewed
                )
            ])
    }
}

private struct ViewedMutationFixture {
    let agentMessages: [WorktreeAnnotationMessage]
    let detail: WorktreeAnnotationSessionDetail
    let repository: WorktreeAnnotationSQLiteRepository
}

private func makeViewedMutationFixture() throws -> ViewedMutationFixture {
    let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
    try WorkspaceLocalMigrations.migrate(databaseQueue)
    let repository = WorktreeAnnotationSQLiteRepository(databaseWriter: databaseQueue)
    var detail = try makeRootDraft(repository: repository)
    detail = try saveMessage(
        repository: repository,
        detail: detail,
        message: try #require(detail.threads.first?.messages.first),
        editToken: "editor-root",
        now: 2
    )
    detail = try addSavedMessage(
        repository: repository,
        detail: detail,
        body: "Agent reply",
        editToken: "agent-reply",
        now: 3
    )
    let messageIDs = try #require(detail.threads.first).messages.map(\.id)
    try databaseQueue.write { database in
        try database.execute(
            sql: "UPDATE annotation_message SET author_kind = 'agent' WHERE id IN (?, ?)",
            arguments: StatementArguments(messageIDs.map(\.databaseValue))
        )
    }
    detail = try repository.fetchSessionDetail(sessionID: detail.session.id)
    return try ViewedMutationFixture(
        agentMessages: #require(detail.threads.first).messages,
        detail: detail,
        repository: repository
    )
}

private func addSavedMessage(
    repository: WorktreeAnnotationSQLiteRepository,
    detail: WorktreeAnnotationSessionDetail,
    body: String,
    editToken: String,
    now: TimeInterval
) throws -> WorktreeAnnotationSessionDetail {
    let draftDetail = try repository.createReplyDraft(
        .init(
            sessionID: detail.session.id,
            threadID: try #require(detail.threads.first?.thread.id),
            expectedThreadRevision: try #require(detail.threads.first?.thread.semanticRevision),
            body: body,
            editToken: editToken,
            now: Date(timeIntervalSince1970: now)
        )
    )
    return try saveMessage(
        repository: repository,
        detail: draftDetail,
        message: try #require(draftDetail.threads.first?.messages.last),
        editToken: editToken,
        now: now + 1
    )
}

private func addSavedRootSession(
    repository: WorktreeAnnotationSQLiteRepository,
    body: String,
    editToken: String,
    now: TimeInterval
) throws -> WorktreeAnnotationSessionDetail {
    let draftDetail = try repository.createRootDraft(
        .init(
            admission: .newSession,
            repositoryID: "repo-1",
            worktreeID: "worktree-1",
            sourceFingerprint: makeSourceFingerprint(worktreeID: "worktree-1"),
            origin: .session,
            body: body,
            editToken: editToken,
            now: Date(timeIntervalSince1970: now)
        )
    )
    return try saveMessage(
        repository: repository,
        detail: draftDetail,
        message: try #require(draftDetail.threads.first?.messages.first),
        editToken: editToken,
        now: now + 1
    )
}

private func saveMessage(
    repository: WorktreeAnnotationSQLiteRepository,
    detail: WorktreeAnnotationSessionDetail,
    message: WorktreeAnnotationMessage,
    editToken: String,
    now: TimeInterval
) throws -> WorktreeAnnotationSessionDetail {
    try repository.saveDraft(
        .init(
            sessionID: detail.session.id,
            messageID: message.id,
            editToken: editToken,
            expectedMessageRevision: message.semanticRevision,
            expectedDraftRevision: try #require(message.draft?.draftRevision),
            now: Date(timeIntervalSince1970: now)
        )
    )
}
