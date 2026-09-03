import Foundation

extension WorktreeAnnotationTransportAdapter {
    func acquireEditToken(
        _ body: BridgeProductWorktreeAnnotationOperation.DraftRevisionBody,
        ownerGeneration: String
    ) async throws -> WorktreeAnnotationSessionID {
        let sessionID = WorktreeAnnotationSessionID(rawValue: body.sessionId)
        _ = try await store.acquireEditToken(
            .init(
                sessionID: sessionID,
                messageID: .init(rawValue: body.messageId),
                editToken: body.editToken,
                expectedMessageRevision: body.expectedMessageRevision,
                expectedDraftRevision: body.expectedDraftRevision,
                now: now()
            ),
            ownerGeneration: ownerGeneration
        )
        return sessionID
    }

    func releaseEditToken(
        _ body: BridgeProductWorktreeAnnotationOperation.DraftRevisionBody,
        ownerGeneration: String
    ) async throws -> WorktreeAnnotationSessionID {
        let sessionID = WorktreeAnnotationSessionID(rawValue: body.sessionId)
        _ = try await store.releaseEditToken(
            .init(
                sessionID: sessionID,
                messageID: .init(rawValue: body.messageId),
                editToken: body.editToken,
                expectedMessageRevision: body.expectedMessageRevision,
                expectedDraftRevision: body.expectedDraftRevision,
                now: now()
            ),
            ownerGeneration: ownerGeneration
        )
        return sessionID
    }
}
