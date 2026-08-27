import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation SQLite repository concurrency")
struct WorktreeAnnotationSQLiteRepositoryConcurrencyTests {
    @Test("unrelated message commits do not conflict with message or reply mutations")
    func unrelatedMessageCommitsDoNotConflictWithMessageOrReplyMutations() throws {
        let repository = try makeRepository()
        var detail = try makeRootDraft(repository: repository)
        let firstThread = try #require(detail.threads.first)
        let firstMessage = try #require(firstThread.messages.first)
        detail = try repository.saveDraft(
            .init(
                sessionID: detail.session.id,
                messageID: firstMessage.id,
                editToken: "editor-root",
                expectedMessageRevision: firstMessage.semanticRevision,
                expectedDraftRevision: 0,
                now: Date(timeIntervalSince1970: 2)
            )
        ).canonicalResult
        let firstSavedMessageRevision = try #require(
            detail.threads.first?.messages.first?.semanticRevision
        )
        let firstSavedThreadRevision = try #require(detail.threads.first?.thread.semanticRevision)

        detail = try repository.createRootDraft(
            .init(
                admission: .selected(detail.session.id),
                repositoryID: detail.session.repositoryID,
                worktreeID: detail.session.worktreeID,
                sourceFingerprint: makeSourceFingerprint(worktreeID: detail.session.worktreeID),
                origin: .session,
                body: "Second independent draft",
                editToken: "editor-second",
                now: Date(timeIntervalSince1970: 3)
            )
        ).canonicalResult
        let secondMessage = try #require(detail.threads.last?.messages.first)
        detail = try repository.saveDraft(
            .init(
                sessionID: detail.session.id,
                messageID: secondMessage.id,
                editToken: "editor-second",
                expectedMessageRevision: secondMessage.semanticRevision,
                expectedDraftRevision: 0,
                now: Date(timeIntervalSince1970: 4)
            )
        ).canonicalResult

        detail = try repository.flushDraft(
            .init(
                sessionID: detail.session.id,
                messageID: firstMessage.id,
                editToken: "editor-first-revision",
                expectedMessageRevision: firstSavedMessageRevision,
                expectedDraftRevision: nil,
                body: "First independent edit",
                now: Date(timeIntervalSince1970: 5)
            )
        ).canonicalResult
        #expect(detail.threads.first?.messages.first?.draft?.body == "First independent edit")

        detail = try repository.createReplyDraft(
            .init(
                sessionID: detail.session.id,
                threadID: firstThread.thread.id,
                expectedThreadRevision: firstSavedThreadRevision,
                body: "Reply after unrelated commit",
                editToken: "editor-reply-after-unrelated",
                now: Date(timeIntervalSince1970: 6)
            )
        ).canonicalResult
        #expect(detail.threads.first?.messages.map(\.ordinal) == [0, 1])
    }
}
