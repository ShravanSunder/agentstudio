import AgentStudioInfrastructure
import Foundation

enum WorktreeAnnotationSourceResolutionError: Error, Equatable, Sendable {
    case invalidSource
    case unavailable
}

struct WorktreeAnnotationCapturedSource: Equatable, Sendable {
    let fingerprint: WorktreeAnnotationSourceFingerprint
    let origin: WorktreeAnnotationThreadOrigin
}

struct WorktreeAnnotationSourceRefreshCapture: Equatable, Sendable {
    let fingerprint: WorktreeAnnotationSourceFingerprint
    let material: WorktreeAnnotationSourceMaterial
}

struct WorktreeAnnotationSourceResolver: Sendable {
    let capture:
        @Sendable (
            BridgeProductWorktreeAnnotationOrigin,
            BridgeProductSurface,
            BridgeProductAdmissionContext
        ) async throws -> WorktreeAnnotationCapturedSource
    let currentFingerprint:
        @Sendable (
            BridgeProductSurface,
            BridgeProductAdmissionContext
        ) async throws -> WorktreeAnnotationSourceFingerprint
    let refresh:
        @Sendable (
            BridgeProductSurface,
            BridgeProductAdmissionContext,
            [WorktreeAnnotationSourceRefreshRequirement]
        ) async throws -> WorktreeAnnotationSourceRefreshCapture

    static let unavailable = Self(
        capture: { _, _, _ in throw WorktreeAnnotationSourceResolutionError.unavailable },
        currentFingerprint: { _, _ in throw WorktreeAnnotationSourceResolutionError.unavailable },
        refresh: { _, _, _ in throw WorktreeAnnotationSourceResolutionError.unavailable }
    )
}

private struct WorktreeAnnotationTransportDemandKey: Hashable {
    let sessionID: WorktreeAnnotationSessionID
    let surface: BridgeProductSurface
}

private struct WorktreeAnnotationCreateRootTransportInput {
    let admission: BridgeProductWorktreeAnnotationAdmission
    let body: String
    let editToken: String
    let origin: BridgeProductWorktreeAnnotationOrigin
    let surface: BridgeProductSurface
    let productAdmission: BridgeProductAdmissionContext
    let ownerGeneration: String
}

private struct WorktreeAnnotationAppliedMessageCommand {
    let sessionID: WorktreeAnnotationSessionID
    let receipt: WorktreeAnnotationMessageCommandReceipt?
}

private struct WorktreeAnnotationAppliedCommand {
    let sessionID: WorktreeAnnotationSessionID?
    let status: WorktreeAnnotationCommandOutcomeStatus
    let receipt: WorktreeAnnotationMessageCommandReceipt?
}

/// Maps committed File/Review product calls into the application-scoped Store.
///
/// Transport acceptance and durable mutation completion are deliberately
/// separate. Every command publishes one bounded correlation outcome after the
/// Store transaction or query returns.
@MainActor
final class WorktreeAnnotationTransportAdapter {
    let now: @Sendable () -> Date
    let contextID: String
    private let originatingWorkspaceID: String?
    let outputCoordinator: WorktreeAnnotationOutputCoordinatorActor?
    let outputLabels: WorktreeAnnotationOutputLabels?
    private let repositoryID: String
    let sourceResolver: WorktreeAnnotationSourceResolver
    let store: WorktreeAnnotationServiceActor
    private let worktreeID: String
    private let outputSelectionAssembler = WorktreeAnnotationOutputSelectionAssembler()
    private var activeProductSessionID: String?
    private var demandGenerationByKey: [WorktreeAnnotationTransportDemandKey: WorktreeAnnotationDemandGeneration] = [:]

    init(
        store: WorktreeAnnotationServiceActor,
        contextID: String,
        repositoryID: String,
        worktreeID: String,
        originatingWorkspaceID: String?,
        sourceResolver: WorktreeAnnotationSourceResolver,
        now: @escaping @Sendable () -> Date = Date.init,
        outputCoordinator: WorktreeAnnotationOutputCoordinatorActor? = nil,
        outputLabels: WorktreeAnnotationOutputLabels? = nil
    ) {
        self.store = store
        self.contextID = contextID
        self.repositoryID = repositoryID
        self.worktreeID = worktreeID
        self.originatingWorkspaceID = originatingWorkspaceID
        self.sourceResolver = sourceResolver
        self.now = now
        self.outputCoordinator = outputCoordinator
        self.outputLabels = outputLabels
    }

    func apply(
        _ request: BridgeProductWorktreeAnnotationCommandRequest,
        surface: BridgeProductSurface,
        correlation: BridgeProductControlCorrelation,
        productAdmission: BridgeProductAdmissionContext
    ) async -> BridgeProductWorktreeAnnotationCommandOutcomeDTO {
        if let activeProductSessionID,
            activeProductSessionID != correlation.workerInstanceId
        {
            outputSelectionAssembler.disconnect(productSessionID: activeProductSessionID)
        }
        activeProductSessionID = correlation.workerInstanceId
        do {
            let applied = try await applyCommand(
                request.operation,
                surface: surface,
                productAdmission: productAdmission,
                ownerGeneration: correlation.workerInstanceId
            )
            let outcome = WorktreeAnnotationCommandOutcome(
                requestID: correlation.requestId,
                surface: surface,
                sessionID: applied.sessionID,
                status: applied.status,
                receipt: applied.receipt
            )
            return BridgeProductWorktreeAnnotationCommandOutcomeDTO(outcome)
        } catch {
            let status: WorktreeAnnotationCommandOutcomeStatus
            if case WorktreeAnnotationRepositoryError.sessionSelectionRequired(let choice) = error {
                status = .admissionRequired(choice)
            } else {
                status = .failed(Self.failureCode(for: error))
            }
            let outcome = WorktreeAnnotationCommandOutcome(
                requestID: correlation.requestId,
                surface: surface,
                sessionID: Self.sessionID(in: request.operation),
                status: status,
                receipt: nil
            )
            return BridgeProductWorktreeAnnotationCommandOutcomeDTO(outcome)
        }
    }

    private func applyCommand(
        _ operation: BridgeProductWorktreeAnnotationOperation,
        surface: BridgeProductSurface,
        productAdmission: BridgeProductAdmissionContext,
        ownerGeneration: String
    ) async throws -> WorktreeAnnotationAppliedCommand {
        switch operation {
        case .outputHistory(let rawSessionID):
            let sessionID = WorktreeAnnotationSessionID(rawValue: rawSessionID)
            let history = try await store.fetchOutputHistory(
                sessionID: sessionID,
                limit: AppPolicies.Bridge.worktreeAnnotationMaximumOutputHistorySummaries
            )
            return .init(sessionID: sessionID, status: .history(history), receipt: nil)
        case .outputSelectionCommit(let body):
            let selection = try outputSelectionAssembler.commit(
                body,
                productSessionID: ownerGeneration
            )
            let output = try await executeOutputPreparation(
                selection,
                surface: surface,
                productAdmission: productAdmission
            )
            return .init(sessionID: output.summary?.sessionID, status: .output(output), receipt: nil)
        case .repeatOutput(let attemptID):
            let output = try await executeOutputRepeat(attemptID: .init(rawValue: attemptID))
            return .init(sessionID: output.summary?.sessionID, status: .output(output), receipt: nil)
        case .createRoot(let admission, let body, let editToken, let origin):
            let applied = try await createRoot(
                .init(
                    admission: admission,
                    body: body,
                    editToken: editToken,
                    origin: origin,
                    surface: surface,
                    productAdmission: productAdmission,
                    ownerGeneration: ownerGeneration
                )
            )
            return .init(sessionID: applied.sessionID, status: .committed, receipt: applied.receipt)
        case .createReply(let body):
            let applied = try await createReply(body, ownerGeneration: ownerGeneration)
            return .init(sessionID: applied.sessionID, status: .committed, receipt: applied.receipt)
        case .flushDraft(let body):
            let applied = try await flushDraft(body, ownerGeneration: ownerGeneration)
            return .init(sessionID: applied.sessionID, status: .committed, receipt: applied.receipt)
        case .saveDraft(let body):
            let applied = try await saveDraft(body, ownerGeneration: ownerGeneration)
            return .init(sessionID: applied.sessionID, status: .committed, receipt: applied.receipt)
        default:
            let sessionID = try await apply(
                operation,
                surface: surface,
                productAdmission: productAdmission,
                ownerGeneration: ownerGeneration
            )
            return .init(sessionID: sessionID, status: .committed, receipt: nil)
        }
    }

    private func apply(
        _ operation: BridgeProductWorktreeAnnotationOperation,
        surface: BridgeProductSurface,
        productAdmission: BridgeProductAdmissionContext,
        ownerGeneration: String
    ) async throws -> WorktreeAnnotationSessionID? {
        switch operation {
        case .discoverSessions:
            _ = try await store.discoverSessions(worktreeID: worktreeID)
            return nil
        case .acquireDemand(let sessionID):
            let typedSessionID = WorktreeAnnotationSessionID(rawValue: sessionID)
            let demandGeneration = try await store.acquireDemand(
                worktreeID: worktreeID,
                contextID: contextID,
                surface: surface,
                sessionID: typedSessionID
            )
            demandGenerationByKey[
                WorktreeAnnotationTransportDemandKey(sessionID: typedSessionID, surface: surface)
            ] = demandGeneration
            return typedSessionID
        case .releaseDemand(let sessionID):
            let typedSessionID = WorktreeAnnotationSessionID(rawValue: sessionID)
            let demandKey = WorktreeAnnotationTransportDemandKey(
                sessionID: typedSessionID,
                surface: surface
            )
            await store.releaseDemand(
                worktreeID: worktreeID,
                contextID: contextID,
                surface: surface,
                sessionID: typedSessionID
            )
            demandGenerationByKey.removeValue(forKey: demandKey)
            return typedSessionID
        case .createRoot(let admission, let body, let editToken, let origin):
            return try await createRoot(
                .init(
                    admission: admission,
                    body: body,
                    editToken: editToken,
                    origin: origin,
                    surface: surface,
                    productAdmission: productAdmission,
                    ownerGeneration: ownerGeneration
                )
            ).sessionID
        case .createReply(let body):
            return try await createReply(body, ownerGeneration: ownerGeneration).sessionID
        case .flushDraft(let body):
            return try await flushDraft(body, ownerGeneration: ownerGeneration).sessionID
        case .acquireEditToken(let body):
            return try await acquireEditToken(body, ownerGeneration: ownerGeneration)
        case .releaseEditToken(let body):
            return try await releaseEditToken(body, ownerGeneration: ownerGeneration)
        case .saveDraft(let body):
            return try await saveDraft(body, ownerGeneration: ownerGeneration).sessionID
        case .revertDraft(let body):
            return try await revertDraft(body, ownerGeneration: ownerGeneration)
        case .setThreadResolution(let body):
            return try await setThreadResolution(body)
        case .setSessionLifecycle(let body):
            let sessionID = WorktreeAnnotationSessionID(rawValue: body.sessionId)
            _ = try await store.setSessionLifecycle(
                .init(
                    sessionID: sessionID,
                    lifecycle: body.lifecycle,
                    expectedSessionRevision: body.expectedSessionRevision,
                    expectedOpenThreadCount: body.expectedOpenThreadCount,
                    confirmsUnresolvedWork: body.confirmsUnresolvedWork,
                    now: now()
                )
            )
            return sessionID
        case .chooseContinuity(let body):
            return try await chooseContinuity(body, surface: surface, productAdmission: productAdmission)
        case .refreshSource(let body):
            return try await refreshSource(body, surface: surface, productAdmission: productAdmission)
        case .outputSelectionBegin(let body):
            try outputSelectionAssembler.begin(body, productSessionID: ownerGeneration)
            return .init(rawValue: body.sessionId)
        case .outputSelectionChunk(let body):
            try outputSelectionAssembler.append(body, productSessionID: ownerGeneration)
            return .init(rawValue: body.sessionId)
        case .outputSelectionCancel(let body):
            try outputSelectionAssembler.cancel(body, productSessionID: ownerGeneration)
            return .init(rawValue: body.sessionId)
        case .outputSelectionCommit:
            throw WorktreeAnnotationTransportAdapterError.outputUnavailable
        case .outputHistory(let sessionID):
            let typedSessionID = WorktreeAnnotationSessionID(rawValue: sessionID)
            _ = try await store.fetchOutputHistory(
                sessionID: typedSessionID,
                limit: AppPolicies.Bridge.worktreeAnnotationMaximumOutputHistorySummaries
            )
            return typedSessionID
        case .repeatOutput:
            throw WorktreeAnnotationTransportAdapterError.outputUnavailable
        case .acknowledgeRecovery:
            try await store.acknowledgeRecovery(at: now())
            return nil
        }
    }

    private func setThreadResolution(
        _ body: BridgeProductWorktreeAnnotationOperation.ThreadResolutionBody
    ) async throws -> WorktreeAnnotationSessionID {
        let sessionID = WorktreeAnnotationSessionID(rawValue: body.sessionId)
        _ = try await store.setThreadResolution(
            .init(
                sessionID: sessionID,
                threadID: .init(rawValue: body.threadId),
                resolution: body.resolution,
                expectedSessionRevision: body.expectedSessionRevision,
                now: now()
            )
        )
        return sessionID
    }

    private func createRoot(
        _ input: WorktreeAnnotationCreateRootTransportInput
    ) async throws -> WorktreeAnnotationAppliedMessageCommand {
        let capturedSource = try await sourceResolver.capture(
            input.origin,
            input.surface,
            input.productAdmission
        )
        try validateFingerprint(capturedSource.fingerprint)
        let detail = try await store.createRootDraft(
            .init(
                admission: Self.sessionAdmission(input.admission),
                repositoryID: repositoryID,
                worktreeID: worktreeID,
                originatingWorkspaceID: originatingWorkspaceID,
                sourceFingerprint: capturedSource.fingerprint,
                origin: capturedSource.origin,
                body: input.body,
                editToken: input.editToken,
                now: now()
            ),
            ownerGeneration: input.ownerGeneration,
            placementContext: .init(contextID: contextID, surface: input.surface)
        )
        guard let createdThread = detail.threads.last,
            let createdMessage = createdThread.messages.first,
            createdMessage.ordinal == 0,
            createdMessage.draft?.activeEditToken == input.editToken
        else {
            throw WorktreeAnnotationTransportAdapterError.messageReceiptUnavailable
        }
        return WorktreeAnnotationAppliedMessageCommand(
            sessionID: detail.session.id,
            receipt: .init(
                messageID: createdMessage.id,
                threadID: createdThread.thread.id,
                sessionRevision: detail.session.semanticRevision,
                messageRevision: createdMessage.semanticRevision,
                draftRevision: createdMessage.draft?.draftRevision,
                savedRevision: createdMessage.savedRevision
            )
        )
    }

    private func createReply(
        _ body: BridgeProductWorktreeAnnotationOperation.MutationBody,
        ownerGeneration: String
    ) async throws -> WorktreeAnnotationAppliedMessageCommand {
        let sessionID = WorktreeAnnotationSessionID(rawValue: body.sessionId)
        let detail = try await store.createReplyDraft(
            .init(
                sessionID: sessionID,
                threadID: .init(rawValue: body.threadId),
                expectedSessionRevision: body.expectedSessionRevision,
                body: body.body,
                editToken: body.editToken,
                now: now()
            ),
            ownerGeneration: ownerGeneration
        )
        guard let thread = detail.threads.first(where: { $0.thread.id.rawValue == body.threadId }),
            let message = thread.messages.last,
            message.draft?.activeEditToken == body.editToken
        else {
            throw WorktreeAnnotationTransportAdapterError.messageReceiptUnavailable
        }
        return appliedMessageCommand(detail: detail, thread: thread, message: message)
    }

    private func flushDraft(
        _ body: BridgeProductWorktreeAnnotationOperation.DraftMutationBody,
        ownerGeneration: String
    ) async throws -> WorktreeAnnotationAppliedMessageCommand {
        let sessionID = WorktreeAnnotationSessionID(rawValue: body.sessionId)
        let detail = try await store.flushDraft(
            .init(
                sessionID: sessionID,
                messageID: .init(rawValue: body.messageId),
                editToken: body.editToken,
                expectedSessionRevision: body.expectedSessionRevision,
                expectedDraftRevision: body.expectedDraftRevision,
                body: body.body,
                now: now()
            ),
            ownerGeneration: ownerGeneration
        )
        if body.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !detail.threads.contains(where: { thread in
                thread.messages.contains(where: { $0.id.rawValue == body.messageId })
            })
        {
            return .init(sessionID: detail.session.id, receipt: nil)
        }
        return try appliedMessageCommand(detail: detail, messageID: body.messageId)
    }

    private func saveDraft(
        _ body: BridgeProductWorktreeAnnotationOperation.DraftRevisionBody,
        ownerGeneration: String
    ) async throws -> WorktreeAnnotationAppliedMessageCommand {
        let sessionID = WorktreeAnnotationSessionID(rawValue: body.sessionId)
        let detail = try await store.saveDraft(
            .init(
                sessionID: sessionID,
                messageID: .init(rawValue: body.messageId),
                editToken: body.editToken,
                expectedSessionRevision: body.expectedSessionRevision,
                expectedDraftRevision: body.expectedDraftRevision,
                now: now()
            ),
            ownerGeneration: ownerGeneration
        )
        return try appliedMessageCommand(detail: detail, messageID: body.messageId)
    }

    private func revertDraft(
        _ body: BridgeProductWorktreeAnnotationOperation.DraftRevisionBody,
        ownerGeneration: String
    ) async throws -> WorktreeAnnotationSessionID {
        let sessionID = WorktreeAnnotationSessionID(rawValue: body.sessionId)
        _ = try await store.revertDraft(
            .init(
                sessionID: sessionID,
                messageID: .init(rawValue: body.messageId),
                editToken: body.editToken,
                expectedSessionRevision: body.expectedSessionRevision,
                expectedDraftRevision: body.expectedDraftRevision,
                now: now()
            ),
            ownerGeneration: ownerGeneration
        )
        return sessionID
    }

    private func appliedMessageCommand(
        detail: WorktreeAnnotationSessionDetail,
        messageID: UUID
    ) throws -> WorktreeAnnotationAppliedMessageCommand {
        for thread in detail.threads {
            if let message = thread.messages.first(where: { $0.id.rawValue == messageID }) {
                return appliedMessageCommand(detail: detail, thread: thread, message: message)
            }
        }
        throw WorktreeAnnotationTransportAdapterError.messageReceiptUnavailable
    }

    private func appliedMessageCommand(
        detail: WorktreeAnnotationSessionDetail,
        thread: WorktreeAnnotationThreadDetail,
        message: WorktreeAnnotationMessage
    ) -> WorktreeAnnotationAppliedMessageCommand {
        WorktreeAnnotationAppliedMessageCommand(
            sessionID: detail.session.id,
            receipt: .init(
                messageID: message.id,
                threadID: thread.thread.id,
                sessionRevision: detail.session.semanticRevision,
                messageRevision: message.semanticRevision,
                draftRevision: message.draft?.draftRevision,
                savedRevision: message.savedRevision
            )
        )
    }

    private func chooseContinuity(
        _ body: BridgeProductWorktreeAnnotationOperation.ContinuityBody,
        surface: BridgeProductSurface,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationSessionID {
        let sessionID = WorktreeAnnotationSessionID(rawValue: body.sessionId)
        let relationship: WorktreeAnnotationSourceRelationship
        let fingerprint: WorktreeAnnotationSourceFingerprint?
        switch body.decision {
        case .acceptCurrentSource:
            let current = try await sourceResolver.currentFingerprint(surface, productAdmission)
            try validateFingerprint(current)
            relationship = .applicable
            fingerprint = current
        case .keepDetached:
            relationship = .detached
            fingerprint = nil
        }
        _ = try await store.setSourceRelationship(
            .init(
                sessionID: sessionID,
                relationship: relationship,
                sourceFingerprint: fingerprint,
                expectedSessionRevision: body.expectedSessionRevision,
                now: now()
            )
        )
        return sessionID
    }

    private func refreshSource(
        _ body: BridgeProductWorktreeAnnotationOperation.SourceRefreshBody,
        surface: BridgeProductSurface,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationSessionID {
        let sessionID = WorktreeAnnotationSessionID(rawValue: body.sessionId)
        let demandKey = WorktreeAnnotationTransportDemandKey(sessionID: sessionID, surface: surface)
        guard let demandGeneration = demandGenerationByKey[demandKey] else {
            throw WorktreeAnnotationServiceError.staleSourceEpoch
        }
        let refreshSnapshot = try await store.sourceRefreshSnapshot(sessionID: sessionID)
        guard demandGenerationByKey[demandKey] == demandGeneration else {
            throw WorktreeAnnotationServiceError.staleSourceEpoch
        }
        let capture = try await sourceResolver.refresh(
            surface,
            productAdmission,
            refreshSnapshot.requirements
        )
        guard demandGenerationByKey[demandKey] == demandGeneration else {
            throw WorktreeAnnotationServiceError.staleSourceEpoch
        }
        try validateFingerprint(capture.fingerprint)
        _ = try await store.refreshSource(
            .init(
                contextID: contextID,
                demandGeneration: demandGeneration,
                sessionID: sessionID,
                surface: surface,
                sourceEpoch: body.sourceEpoch,
                expectedSnapshot: refreshSnapshot,
                currentFingerprint: capture.fingerprint,
                material: capture.material,
                now: now()
            )
        )
        return sessionID
    }

    private func validateFingerprint(_ fingerprint: WorktreeAnnotationSourceFingerprint) throws {
        guard fingerprint.repositoryID == repositoryID,
            fingerprint.worktreeID == worktreeID
        else {
            throw WorktreeAnnotationSourceResolutionError.invalidSource
        }
    }

    private static func sessionAdmission(
        _ admission: BridgeProductWorktreeAnnotationAdmission
    ) -> WorktreeAnnotationSQLiteRepository.SessionAdmission {
        switch admission {
        case .implicitOrSingle:
            .implicitOrSingle
        case .newSession:
            .newSession
        case .selected(let sessionID):
            .selected(.init(rawValue: sessionID))
        }
    }

    private static func sessionID(
        in operation: BridgeProductWorktreeAnnotationOperation
    ) -> WorktreeAnnotationSessionID? {
        switch operation {
        case .acquireDemand(let id), .releaseDemand(let id), .outputHistory(let id):
            .init(rawValue: id)
        case .createReply(let body):
            .init(rawValue: body.sessionId)
        case .flushDraft(let body):
            .init(rawValue: body.sessionId)
        case .acquireEditToken(let body), .releaseEditToken(let body),
            .saveDraft(let body), .revertDraft(let body):
            .init(rawValue: body.sessionId)
        case .setThreadResolution(let body):
            .init(rawValue: body.sessionId)
        case .setSessionLifecycle(let body):
            .init(rawValue: body.sessionId)
        case .chooseContinuity(let body):
            .init(rawValue: body.sessionId)
        case .refreshSource(let body):
            .init(rawValue: body.sessionId)
        case .outputSelectionBegin(let body):
            .init(rawValue: body.sessionId)
        case .outputSelectionChunk(let body):
            .init(rawValue: body.sessionId)
        case .outputSelectionCommit(let body), .outputSelectionCancel(let body):
            .init(rawValue: body.sessionId)
        case .acknowledgeRecovery, .createRoot, .discoverSessions, .repeatOutput:
            nil
        }
    }

    private static func failureCode(for error: any Error) -> WorktreeAnnotationCommandFailureCode {
        if let repositoryError = error as? WorktreeAnnotationRepositoryError {
            switch repositoryError {
            case .conflict: .conflict
            case .editTokenConflict: .editTokenConflict
            case .messageLocked: .messageLocked
            case .sessionReadOnly: .sessionReadOnly
            case .sessionSelectionRequired: .sessionSelectionRequired
            case .openThreadCountConflict: .openThreadCountConflict
            case .unresolvedWorkConfirmationRequired: .unresolvedWorkConfirmationRequired
            case .notFound: .notFound
            case .invalidState, .duplicateSelection, .emptySelection:
                .unexpected
            }
        } else if let storeError = error as? WorktreeAnnotationServiceError {
            switch storeError {
            case .recoveryAcknowledgementRequired: .recoveryAcknowledgementRequired
            case .staleSourceEpoch: .conflict
            case .unavailable: .unavailable
            }
        } else if let sourceError = error as? WorktreeAnnotationSourceResolutionError {
            switch sourceError {
            case .invalidSource: .invalidSource
            case .unavailable: .unavailable
            }
        } else if let adapterError = error as? WorktreeAnnotationTransportAdapterError {
            switch adapterError {
            case .messageReceiptUnavailable: .unexpected
            case .outputUnavailable: .outputUnavailable
            }
        } else if error is WorktreeAnnotationOutputSelectionAssemblerError {
            .outputUnavailable
        } else {
            .unexpected
        }
    }
}

enum WorktreeAnnotationTransportAdapterError: Error {
    case messageReceiptUnavailable
    case outputUnavailable
}
