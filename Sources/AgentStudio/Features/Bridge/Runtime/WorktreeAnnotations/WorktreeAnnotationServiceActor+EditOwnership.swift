import Foundation

struct WorktreeAnnotationEditTokenCommandProps: Sendable {
    let sessionID: WorktreeAnnotationSessionID
    let messageID: WorktreeAnnotationMessageID
    let editToken: String
    let expectedMessageRevision: Int
    let expectedDraftRevision: Int
    let now: Date
}

final class WorktreeAnnotationEditOwnershipRegistry {
    private var ownerGenerationByToken: [String: String] = [:]

    var liveTokens: Set<String> { Set(ownerGenerationByToken.keys) }

    func validateAvailable(token: String, ownerGeneration: String) throws {
        if let existingOwner = ownerGenerationByToken[token], existingOwner != ownerGeneration {
            throw WorktreeAnnotationRepositoryError.editTokenConflict
        }
    }

    func register(token: String, ownerGeneration: String) throws {
        try validateAvailable(token: token, ownerGeneration: ownerGeneration)
        ownerGenerationByToken[token] = ownerGeneration
    }

    func require(token: String, ownerGeneration: String) throws {
        guard ownerGenerationByToken[token] == ownerGeneration else {
            throw WorktreeAnnotationRepositoryError.editTokenConflict
        }
    }

    func release(token: String) {
        ownerGenerationByToken.removeValue(forKey: token)
    }

    func invalidate(ownerGeneration: String) {
        ownerGenerationByToken = ownerGenerationByToken.filter { $0.value != ownerGeneration }
    }
}

extension WorktreeAnnotationServiceActor {
    func createRootDraft(
        _ props: WorktreeAnnotationSQLiteRepository.CreateRootDraftProps,
        ownerGeneration: String
    ) async throws -> WorktreeAnnotationSessionDetail {
        try editOwnership.register(token: props.editToken, ownerGeneration: ownerGeneration)
        do {
            return try await createRootDraft(props)
        } catch {
            editOwnership.release(token: props.editToken)
            throw error
        }
    }

    func createRootDraft(
        _ props: WorktreeAnnotationSQLiteRepository.CreateRootDraftProps,
        ownerGeneration: String,
        placementContext: WorktreeAnnotationRootPlacementContext
    ) async throws -> WorktreeAnnotationSessionDetail {
        try editOwnership.register(token: props.editToken, ownerGeneration: ownerGeneration)
        do {
            return try await createRootDraft(props, placementContext: placementContext)
        } catch {
            editOwnership.release(token: props.editToken)
            throw error
        }
    }

    func createReplyDraft(
        _ props: WorktreeAnnotationSQLiteRepository.CreateReplyDraftProps,
        ownerGeneration: String
    ) async throws -> WorktreeAnnotationSessionDetail {
        try editOwnership.register(token: props.editToken, ownerGeneration: ownerGeneration)
        do {
            return try await createReplyDraft(props)
        } catch {
            editOwnership.release(token: props.editToken)
            throw error
        }
    }

    func flushDraft(
        _ props: WorktreeAnnotationSQLiteRepository.FlushDraftProps,
        ownerGeneration: String
    ) async throws -> WorktreeAnnotationSessionDetail {
        if props.expectedDraftRevision == nil {
            try editOwnership.register(token: props.editToken, ownerGeneration: ownerGeneration)
        } else {
            try editOwnership.require(token: props.editToken, ownerGeneration: ownerGeneration)
        }
        do {
            let detail = try await flushDraft(props)
            if !detail.threads.flatMap(\.messages).contains(where: { $0.id == props.messageID }) {
                editOwnership.release(token: props.editToken)
            }
            return detail
        } catch {
            if props.expectedDraftRevision == nil {
                editOwnership.release(token: props.editToken)
            }
            throw error
        }
    }

    func saveDraft(
        _ props: WorktreeAnnotationSQLiteRepository.SaveDraftProps,
        ownerGeneration: String
    ) async throws -> WorktreeAnnotationSessionDetail {
        try editOwnership.require(token: props.editToken, ownerGeneration: ownerGeneration)
        let detail = try await saveDraft(props)
        editOwnership.release(token: props.editToken)
        return detail
    }

    func revertDraft(
        _ props: WorktreeAnnotationSQLiteRepository.RevertDraftProps,
        ownerGeneration: String
    ) async throws -> WorktreeAnnotationSessionDetail {
        try editOwnership.require(token: props.editToken, ownerGeneration: ownerGeneration)
        let detail = try await revertDraft(props)
        editOwnership.release(token: props.editToken)
        return detail
    }

    func acquireEditToken(
        _ props: WorktreeAnnotationEditTokenCommandProps,
        ownerGeneration: String
    ) async throws -> WorktreeAnnotationSessionDetail {
        try requireMutationAllowed()
        try editOwnership.validateAvailable(token: props.editToken, ownerGeneration: ownerGeneration)
        let committed = try await repositoryAccess.acquireEditToken(
            .init(
                sessionID: props.sessionID,
                messageID: props.messageID,
                editToken: props.editToken,
                expectedMessageRevision: props.expectedMessageRevision,
                expectedDraftRevision: props.expectedDraftRevision,
                liveEditTokens: editOwnership.liveTokens,
                now: props.now
            )
        )
        try editOwnership.register(token: props.editToken, ownerGeneration: ownerGeneration)
        publishSnapshotRequired(worktreeID: committed.session.worktreeID)
        return committed
    }

    func releaseEditToken(
        _ props: WorktreeAnnotationEditTokenCommandProps,
        ownerGeneration: String
    ) async throws -> WorktreeAnnotationSessionDetail {
        try editOwnership.require(token: props.editToken, ownerGeneration: ownerGeneration)
        let committed = try await publishCommittedMutation {
            try await repositoryAccess.releaseEditToken(
                .init(
                    sessionID: props.sessionID,
                    messageID: props.messageID,
                    editToken: props.editToken,
                    expectedMessageRevision: props.expectedMessageRevision,
                    expectedDraftRevision: props.expectedDraftRevision,
                    now: props.now
                )
            )
        }
        editOwnership.release(token: props.editToken)
        return committed
    }

    func invalidateEditOwnerGeneration(_ ownerGeneration: String) {
        editOwnership.invalidate(ownerGeneration: ownerGeneration)
    }
}
