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

/// Maps committed File/Review product calls into the application-scoped Store.
///
/// Transport acceptance and durable mutation completion are deliberately
/// separate. Every command publishes one bounded correlation outcome after the
/// Store transaction or query returns.
@MainActor
final class WorktreeAnnotationTransportAdapter {
    let now: @Sendable () -> Date
    private let contextID: String
    private let originatingWorkspaceID: String?
    private let outputCoordinator: WorktreeAnnotationOutputCoordinator?
    private let outputLabels: WorktreeAnnotationOutputLabels?
    private let projection: WorktreeAnnotationProjectionAtom
    private let repositoryID: String
    private let sourceResolver: WorktreeAnnotationSourceResolver
    let store: WorktreeAnnotationStore
    private let worktreeID: String
    private var demandGenerationByKey: [WorktreeAnnotationTransportDemandKey: WorktreeAnnotationDemandGeneration] = [:]

    init(
        store: WorktreeAnnotationStore,
        contextID: String,
        repositoryID: String,
        worktreeID: String,
        originatingWorkspaceID: String?,
        sourceResolver: WorktreeAnnotationSourceResolver,
        now: @escaping @Sendable () -> Date = Date.init,
        outputCoordinator: WorktreeAnnotationOutputCoordinator? = nil,
        outputLabels: WorktreeAnnotationOutputLabels? = nil
    ) {
        self.store = store
        self.contextID = contextID
        self.projection = store.projection
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
    ) async {
        do {
            let sessionID: WorktreeAnnotationSessionID?
            let status: WorktreeAnnotationCommandOutcomeStatus
            switch request.operation {
            case .prepareOutput(let body):
                let output = try await executeOutputPreparation(body, surface: surface)
                sessionID = output.summary?.sessionID
                status = .output(output)
            case .repeatOutput(let attemptID):
                let output = try await executeOutputRepeat(
                    attemptID: .init(rawValue: attemptID)
                )
                sessionID = output.summary?.sessionID
                status = .output(output)
            default:
                sessionID = try await apply(
                    request.operation,
                    surface: surface,
                    productAdmission: productAdmission,
                    ownerGeneration: correlation.workerInstanceId
                )
                status = .committed
            }
            projection.publish(
                commandOutcome: .init(
                    requestID: correlation.requestId,
                    surface: surface,
                    sessionID: sessionID,
                    status: status
                )
            )
        } catch {
            let status: WorktreeAnnotationCommandOutcomeStatus
            if case WorktreeAnnotationRepositoryError.sessionSelectionRequired(let choice) = error {
                status = .admissionRequired(choice)
            } else {
                status = .failed(Self.failureCode(for: error))
            }
            projection.publish(
                commandOutcome: .init(
                    requestID: correlation.requestId,
                    surface: surface,
                    sessionID: Self.sessionID(in: request.operation),
                    status: status
                )
            )
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
            store.releaseDemand(
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
            )
        case .createReply(let body):
            return try await createReply(body, ownerGeneration: ownerGeneration)
        case .flushDraft(let body):
            return try await flushDraft(body, ownerGeneration: ownerGeneration)
        case .acquireEditToken(let body):
            return try await acquireEditToken(body, ownerGeneration: ownerGeneration)
        case .releaseEditToken(let body):
            return try await releaseEditToken(body, ownerGeneration: ownerGeneration)
        case .saveDraft(let body):
            return try await saveDraft(body, ownerGeneration: ownerGeneration)
        case .revertDraft(let body):
            return try await revertDraft(body, ownerGeneration: ownerGeneration)
        case .setThreadResolution(let body):
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
        case .prepareOutput:
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

    private func createRoot(
        _ input: WorktreeAnnotationCreateRootTransportInput
    ) async throws -> WorktreeAnnotationSessionID {
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
        return detail.session.id
    }

    private func createReply(
        _ body: BridgeProductWorktreeAnnotationOperation.MutationBody,
        ownerGeneration: String
    ) async throws -> WorktreeAnnotationSessionID {
        let sessionID = WorktreeAnnotationSessionID(rawValue: body.sessionId)
        _ = try await store.createReplyDraft(
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
        return sessionID
    }

    private func flushDraft(
        _ body: BridgeProductWorktreeAnnotationOperation.DraftMutationBody,
        ownerGeneration: String
    ) async throws -> WorktreeAnnotationSessionID {
        let sessionID = WorktreeAnnotationSessionID(rawValue: body.sessionId)
        _ = try await store.flushDraft(
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
        return sessionID
    }

    private func saveDraft(
        _ body: BridgeProductWorktreeAnnotationOperation.DraftRevisionBody,
        ownerGeneration: String
    ) async throws -> WorktreeAnnotationSessionID {
        let sessionID = WorktreeAnnotationSessionID(rawValue: body.sessionId)
        _ = try await store.saveDraft(
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
            throw WorktreeAnnotationStoreError.staleSourceEpoch
        }
        let refreshSnapshot = try await store.sourceRefreshSnapshot(sessionID: sessionID)
        guard demandGenerationByKey[demandKey] == demandGeneration else {
            throw WorktreeAnnotationStoreError.staleSourceEpoch
        }
        let capture = try await sourceResolver.refresh(
            surface,
            productAdmission,
            refreshSnapshot.requirements
        )
        guard demandGenerationByKey[demandKey] == demandGeneration else {
            throw WorktreeAnnotationStoreError.staleSourceEpoch
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

    private func executeOutputPreparation(
        _ body: BridgeProductWorktreeAnnotationOperation.OutputPreparationBody,
        surface: BridgeProductSurface
    ) async throws -> WorktreeAnnotationOutputCommandOutcome {
        guard let outputCoordinator, let outputLabels else {
            throw WorktreeAnnotationTransportAdapterError.outputUnavailable
        }
        let sessionID = WorktreeAnnotationSessionID(rawValue: body.sessionId)
        let context = try await store.outputSnapshotContext(
            sessionID: sessionID,
            contextID: contextID,
            surface: surface
        )
        let outputKind: WorktreeAnnotationOutputKind =
            switch body.outputKind {
            case .clipboardMarkdown: .clipboardMarkdown
            case .jsonFile: .jsonFile
            }
        let eligibleMessages = context.sessionDetail.threads.flatMap(\.messages).filter {
            $0.savedBody != nil && $0.savedRevision != nil && $0.draft == nil && $0.status == .editable
        }
        let selectedMessages: [WorktreeAnnotationMessage]
        switch body.selection {
        case .explicit(let messageIds):
            let selectedIDs = Set(messageIds.map(WorktreeAnnotationMessageID.init(rawValue:)))
            selectedMessages = eligibleMessages.filter { selectedIDs.contains($0.id) }
            guard selectedMessages.count == selectedIDs.count else {
                throw WorktreeAnnotationRepositoryError.invalidState
            }
        case .allEligible(let excludedMessageIds):
            let excludedIDs = Set(excludedMessageIds.map(WorktreeAnnotationMessageID.init(rawValue:)))
            let knownIDs = Set(context.sessionDetail.threads.flatMap(\.messages).map(\.id))
            guard excludedIDs.isSubset(of: knownIDs) else {
                throw WorktreeAnnotationRepositoryError.notFound
            }
            selectedMessages = eligibleMessages.filter { !excludedIDs.contains($0.id) }
        }
        guard !selectedMessages.isEmpty else { throw WorktreeAnnotationRepositoryError.emptySelection }
        let comparisonLabel =
            try outputLabels.comparisonLabel
            ?? WorktreeAnnotationComparisonLabelProjector.project(
                context.sessionDetail.session.acceptedSourceFingerprint.reviewComparisonOrigin
            )
        let result = try await outputCoordinator.executeNew(
            .init(
                outputKind: outputKind,
                sessionDetail: context.sessionDetail,
                selectedMessages: try selectedMessages.map { message in
                    guard let savedRevision = message.savedRevision else {
                        throw WorktreeAnnotationRepositoryError.invalidState
                    }
                    return .init(messageID: message.id, expectedSavedRevision: savedRevision)
                },
                placementsByThreadID: context.placementsByThreadID,
                sessionLabel: outputLabels.sessionLabel,
                worktreeLabel: outputLabels.worktreeLabel,
                comparisonLabel: comparisonLabel
            )
        )
        return result.commandOutcome
    }

    private func executeOutputRepeat(
        attemptID: WorktreeAnnotationOutputAttemptID
    ) async throws -> WorktreeAnnotationOutputCommandOutcome {
        guard let outputCoordinator else {
            throw WorktreeAnnotationTransportAdapterError.outputUnavailable
        }
        return try await outputCoordinator.executeRepeat(sourceAttemptID: attemptID).commandOutcome
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
        case .prepareOutput(let body):
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
        } else if let storeError = error as? WorktreeAnnotationStoreError {
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
        } else if error is WorktreeAnnotationTransportAdapterError {
            .outputUnavailable
        } else {
            .unexpected
        }
    }
}

private enum WorktreeAnnotationTransportAdapterError: Error {
    case outputUnavailable
}
