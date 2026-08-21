import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

enum WorktreeAnnotationServiceError: Error, Equatable, Sendable {
    case recoveryAcknowledgementRequired
    case staleSourceEpoch
    case unavailable
}

struct WorktreeAnnotationDemandGeneration: Equatable, Sendable {
    let id: UUID
}

private struct WorktreeAnnotationSourceRefreshFence: Equatable {
    let demandGeneration: WorktreeAnnotationDemandGeneration
    let sourceEpoch: Int
}

struct WorktreeAnnotationSourceRefreshProps: Sendable {
    let contextID: String
    let demandGeneration: WorktreeAnnotationDemandGeneration
    let sessionID: WorktreeAnnotationSessionID
    let surface: BridgeProductSurface
    let sourceEpoch: Int
    let expectedSnapshot: WorktreeAnnotationSourceRefreshSnapshot
    let currentFingerprint: WorktreeAnnotationSourceFingerprint
    let material: WorktreeAnnotationSourceMaterial
    let now: Date
}

struct WorktreeAnnotationSourceRefreshRequirement: Equatable, Sendable {
    let threadID: WorktreeAnnotationThreadID
    let origin: WorktreeAnnotationThreadOrigin
}

struct WorktreeAnnotationSourceRefreshSnapshot: Equatable, Sendable {
    let sessionID: WorktreeAnnotationSessionID
    let acceptedSourceFingerprint: WorktreeAnnotationSourceFingerprint
    let requirements: [WorktreeAnnotationSourceRefreshRequirement]
}

struct WorktreeAnnotationRootPlacementContext: Sendable {
    let contextID: String
    let surface: BridgeProductSurface
}

enum WorktreeAnnotationChange: Equatable, Sendable {
    case snapshotRequired(
        worktreeID: String,
        operationCorrelationID: String,
        deliveryAttempt: Int
    )
}

struct WorktreeAnnotationChangeObserver: Sendable {
    let stream: AsyncStream<WorktreeAnnotationChange>
    let token: UUID
}

struct WorktreeAnnotationServiceProjectionCapture: Sendable {
    let recoveryState: WorktreeAnnotationRecoveryState
    let repositorySnapshot: WorktreeAnnotationRepositoryProjectionSnapshot
    let revision: Int
}

private struct WorktreeAnnotationChangeObserverState {
    let continuation: AsyncStream<WorktreeAnnotationChange>.Continuation
    let worktreeID: String
}

/// Application-scoped actor for annotation commands, queries, and demand.
///
/// Semantic mutations await the repository transaction before broadcasting a
/// compact invalidation. SQLite remains the only annotation authority.
package actor WorktreeAnnotationServiceActor {
    let repositoryAccess: any WorktreeAnnotationRepositoryAccess
    private let lifecycleTraceRecorder: (any BridgeProductMetadataLifecycleTraceRecording)?
    private var activeDemandGenerationByContextKey:
        [WorktreeAnnotationPlacementContextKey: WorktreeAnnotationDemandGeneration] = [:]
    private var latestSourceRefreshFenceByContextKey:
        [WorktreeAnnotationPlacementContextKey: WorktreeAnnotationSourceRefreshFence] = [:]
    private var changeObserverByToken: [UUID: WorktreeAnnotationChangeObserverState] = [:]
    private var projectionRevision = 0
    let editOwnership = WorktreeAnnotationEditOwnershipRegistry()
    private var recoveryState: WorktreeAnnotationRecoveryState = .available
    private var unacknowledgedRecoveryWitness: WorktreeAnnotationRecoveryProvenance?

    init(
        repositoryAccess: any WorktreeAnnotationRepositoryAccess,
        lifecycleTraceRecorder: (any BridgeProductMetadataLifecycleTraceRecording)? = nil
    ) {
        self.repositoryAccess = repositoryAccess
        self.lifecycleTraceRecorder = lifecycleTraceRecorder
    }

    package init(
        sqliteAdapter: WorktreeAnnotationSQLiteDatastoreAdapter,
        traceRuntime: AgentStudioTraceRuntime? = nil
    ) {
        repositoryAccess = sqliteAdapter
        lifecycleTraceRecorder = traceRuntime.map {
            BridgeProductMetadataLifecycleTraceRecorder(
                recorder: BridgePerformanceTraceRecorder(traceRuntime: $0)
            )
        }
    }

    func registerChangeObserver(worktreeID: String) -> WorktreeAnnotationChangeObserver {
        let token = UUIDv7.generate()
        let stream = AsyncStream<WorktreeAnnotationChange>(
            bufferingPolicy: .bufferingNewest(1)
        ) { continuation in
            changeObserverByToken[token] = WorktreeAnnotationChangeObserverState(
                continuation: continuation,
                worktreeID: worktreeID
            )
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeChangeObserver(token: token) }
            }
        }
        return WorktreeAnnotationChangeObserver(stream: stream, token: token)
    }

    func removeChangeObserver(token: UUID) {
        changeObserverByToken.removeValue(forKey: token)?.continuation.finish()
    }

    func changeObserverCount() -> Int {
        changeObserverByToken.count
    }

    @discardableResult
    package func restoreRecoveryState() async -> PersistenceRecoveryEvent? {
        do {
            let witness = try await repositoryAccess.fetchUnacknowledgedRecoveryProvenance()
            unacknowledgedRecoveryWitness = witness
            recoveryState = witness.map(WorktreeAnnotationRecoveryState.recoveredDegraded) ?? .available
            await publishSnapshotRequiredForEveryObservedWorktree()
            return witness.map {
                PersistenceRecoveryEvent(
                    store: .worktreeAnnotations,
                    workspaceId: nil,
                    recovery: .quarantinedAndReset,
                    quarantinedFilename: $0.quarantinedFilenames.joined(separator: ", ")
                )
            }
        } catch {
            unacknowledgedRecoveryWitness = nil
            recoveryState = .unavailable
            await publishSnapshotRequiredForEveryObservedWorktree()
            return PersistenceRecoveryEvent(
                store: .worktreeAnnotations,
                workspaceId: nil,
                recovery: .resetToDefaults
            )
        }
    }

    func discoverSessions(worktreeID: String) async throws -> [WorktreeAnnotationSession] {
        try requireAvailableForReads()
        return try await repositoryAccess.discoverSessions(worktreeID: worktreeID)
    }

    func captureProjection(
        worktreeID: String,
        demandedSessionIDs: [WorktreeAnnotationSessionID]
    ) async throws -> WorktreeAnnotationServiceProjectionCapture {
        try requireAvailableForReads()
        let capturedRevision = projectionRevision
        let capturedRecoveryState = recoveryState
        let repositorySnapshot = try await repositoryAccess.fetchProjectionSnapshot(
            worktreeID: worktreeID,
            demandedSessionIDs: demandedSessionIDs
        )
        guard projectionRevision == capturedRevision,
            recoveryState == capturedRecoveryState
        else {
            throw WorktreeAnnotationServiceError.staleSourceEpoch
        }
        return WorktreeAnnotationServiceProjectionCapture(
            recoveryState: capturedRecoveryState,
            repositorySnapshot: repositorySnapshot,
            revision: capturedRevision
        )
    }

    func acquireDemand(
        worktreeID: String,
        contextID: String,
        surface: BridgeProductSurface,
        sessionID: WorktreeAnnotationSessionID
    ) async throws -> WorktreeAnnotationDemandGeneration {
        try requireAvailableForReads()
        guard !contextID.isEmpty else { throw WorktreeAnnotationServiceError.staleSourceEpoch }

        let contextKey = WorktreeAnnotationPlacementContextKey(
            contextID: contextID,
            surface: surface,
            sessionID: sessionID
        )
        let demandGeneration = WorktreeAnnotationDemandGeneration(id: UUIDv7.generate())
        activeDemandGenerationByContextKey.updateValue(
            demandGeneration,
            forKey: contextKey
        )
        let detail: WorktreeAnnotationSessionDetail
        do {
            detail = try await repositoryAccess.fetchSessionDetail(sessionID: sessionID)
        } catch {
            rollbackDemandRegistration(
                contextKey: contextKey,
                demandGeneration: demandGeneration
            )
            throw error
        }
        guard activeDemandGenerationByContextKey[contextKey] == demandGeneration else {
            throw WorktreeAnnotationServiceError.staleSourceEpoch
        }
        guard detail.session.worktreeID == worktreeID else {
            rollbackDemandRegistration(
                contextKey: contextKey,
                demandGeneration: demandGeneration
            )
            throw WorktreeAnnotationRepositoryError.notFound
        }
        return demandGeneration
    }

    func releaseDemand(
        worktreeID: String,
        contextID: String,
        surface: BridgeProductSurface,
        sessionID: WorktreeAnnotationSessionID
    ) async {
        let contextKey = WorktreeAnnotationPlacementContextKey(
            contextID: contextID,
            surface: surface,
            sessionID: sessionID
        )
        activeDemandGenerationByContextKey.removeValue(forKey: contextKey)
    }

    func sourceRefreshSnapshot(
        sessionID: WorktreeAnnotationSessionID
    ) async throws -> WorktreeAnnotationSourceRefreshSnapshot {
        try requireAvailableForReads()
        let detail = try await repositoryAccess.fetchSessionDetail(sessionID: sessionID)
        return Self.sourceRefreshSnapshot(from: detail)
    }

    @discardableResult
    func createRootDraft(
        _ props: WorktreeAnnotationSQLiteRepository.CreateRootDraftProps
    ) async throws -> WorktreeAnnotationSessionDetail {
        try requireMutationAllowed()
        return try await publishCommittedMutation { try await repositoryAccess.createRootDraft(props) }
    }

    @discardableResult
    func createRootDraft(
        _ props: WorktreeAnnotationSQLiteRepository.CreateRootDraftProps,
        placementContext: WorktreeAnnotationRootPlacementContext
    ) async throws -> WorktreeAnnotationSessionDetail {
        try requireMutationAllowed()
        _ = placementContext
        return try await publishCommittedMutation { try await repositoryAccess.createRootDraft(props) }
    }

    @discardableResult
    func flushDraft(
        _ props: WorktreeAnnotationSQLiteRepository.FlushDraftProps
    ) async throws -> WorktreeAnnotationSessionDetail {
        try await publishCommittedMutation { try await repositoryAccess.flushDraft(props) }
    }

    @discardableResult
    func saveDraft(
        _ props: WorktreeAnnotationSQLiteRepository.SaveDraftProps
    ) async throws -> WorktreeAnnotationSessionDetail {
        try await publishCommittedMutation { try await repositoryAccess.saveDraft(props) }
    }

    @discardableResult
    func revertDraft(
        _ props: WorktreeAnnotationSQLiteRepository.RevertDraftProps
    ) async throws -> WorktreeAnnotationSessionDetail {
        try await publishCommittedMutation { try await repositoryAccess.revertDraft(props) }
    }

    @discardableResult
    func createReplyDraft(
        _ props: WorktreeAnnotationSQLiteRepository.CreateReplyDraftProps
    ) async throws -> WorktreeAnnotationSessionDetail {
        try await publishCommittedMutation { try await repositoryAccess.createReplyDraft(props) }
    }

    @discardableResult
    func setThreadResolution(
        _ props: WorktreeAnnotationSQLiteRepository.SetThreadResolutionProps
    ) async throws -> WorktreeAnnotationSessionDetail {
        try await publishCommittedMutation { try await repositoryAccess.setThreadResolution(props) }
    }

    @discardableResult
    func setSessionLifecycle(
        _ props: WorktreeAnnotationSQLiteRepository.SetSessionLifecycleProps
    ) async throws -> WorktreeAnnotationSessionDetail {
        try await publishCommittedMutation { try await repositoryAccess.setSessionLifecycle(props) }
    }

    @discardableResult
    func setSourceRelationship(
        _ props: WorktreeAnnotationSQLiteRepository.SetSourceRelationshipProps
    ) async throws -> WorktreeAnnotationSessionDetail {
        try await publishCommittedMutation { try await repositoryAccess.setSourceRelationship(props) }
    }

    @discardableResult
    func refreshSource(
        _ props: WorktreeAnnotationSourceRefreshProps
    ) async throws -> WorktreeAnnotationSessionDetail {
        try requireAvailableForReads()
        return try await publishCorrelatedMutation(
            worktreeID: { $0.session.worktreeID },
            { try await performSourceRefresh(props) }
        )
    }

    private func performSourceRefresh(
        _ props: WorktreeAnnotationSourceRefreshProps
    ) async throws -> WorktreeAnnotationSessionDetail {
        try requireAvailableForReads()
        guard !props.contextID.isEmpty, props.sourceEpoch >= 0 else {
            throw WorktreeAnnotationServiceError.staleSourceEpoch
        }
        let contextKey = WorktreeAnnotationPlacementContextKey(
            contextID: props.contextID,
            surface: props.surface,
            sessionID: props.sessionID
        )
        guard activeDemandGenerationByContextKey[contextKey] == props.demandGeneration else {
            throw WorktreeAnnotationServiceError.staleSourceEpoch
        }
        let refreshFence = WorktreeAnnotationSourceRefreshFence(
            demandGeneration: props.demandGeneration,
            sourceEpoch: props.sourceEpoch
        )
        if let latestFence = latestSourceRefreshFenceByContextKey[contextKey] {
            guard
                refreshFence.demandGeneration != latestFence.demandGeneration
                    || refreshFence.sourceEpoch > latestFence.sourceEpoch
            else {
                throw WorktreeAnnotationServiceError.staleSourceEpoch
            }
        }
        latestSourceRefreshFenceByContextKey[contextKey] = refreshFence

        let loadedDetail = try await repositoryAccess.fetchSessionDetail(sessionID: props.sessionID)
        guard activeDemandGenerationByContextKey[contextKey] == props.demandGeneration,
            latestSourceRefreshFenceByContextKey[contextKey] == refreshFence
        else {
            throw WorktreeAnnotationServiceError.staleSourceEpoch
        }
        guard Self.sourceRefreshSnapshot(from: loadedDetail) == props.expectedSnapshot else {
            throw WorktreeAnnotationServiceError.staleSourceEpoch
        }
        let evaluation = try WorktreeAnnotationSourceEvaluator.evaluate(
            .init(
                session: loadedDetail.session,
                threads: loadedDetail.threads.map(\.thread),
                surface: props.surface,
                sourceEpoch: String(props.sourceEpoch),
                currentFingerprint: props.currentFingerprint,
                material: props.material
            )
        )
        let committedDetail: WorktreeAnnotationSessionDetail
        if evaluation.sourceRelationship != loadedDetail.session.sourceRelationship
            || evaluation.acceptedSourceFingerprint.map({
                $0 != loadedDetail.session.acceptedSourceFingerprint
            }) == true
        {
            committedDetail = try await repositoryAccess.setSourceRelationship(
                .init(
                    sessionID: props.sessionID,
                    relationship: evaluation.sourceRelationship,
                    sourceFingerprint: evaluation.acceptedSourceFingerprint,
                    expectedSessionRevision: loadedDetail.session.semanticRevision,
                    now: props.now
                )
            )
        } else {
            committedDetail = loadedDetail
        }
        guard activeDemandGenerationByContextKey[contextKey] == props.demandGeneration,
            latestSourceRefreshFenceByContextKey[contextKey] == refreshFence
        else {
            throw WorktreeAnnotationServiceError.staleSourceEpoch
        }
        return committedDetail
    }

    @discardableResult
    func prepareOutput(
        _ props: WorktreeAnnotationSQLiteRepository.PrepareOutputProps
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput {
        try requireMutationAllowed()
        guard props.expectedProjectionRevision == projectionRevision else {
            throw WorktreeAnnotationServiceError.staleSourceEpoch
        }
        let committed = try await publishCorrelatedMutation(
            worktreeID: { $0.sessionDetail.session.worktreeID },
            { try await repositoryAccess.prepareOutput(props) }
        )
        return committed.preparedOutput
    }

    func inspectOutputAttempt(
        attemptID: WorktreeAnnotationOutputAttemptID
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput {
        try requireAvailableForReads()
        return try await repositoryAccess.inspectOutputAttempt(attemptID: attemptID)
    }

    func outputSessionDetail(
        sessionID: WorktreeAnnotationSessionID
    ) async throws -> WorktreeAnnotationSessionDetail {
        try requireAvailableForReads()
        return try await repositoryAccess.fetchSessionDetail(sessionID: sessionID)
    }

    func outputSessionDetail(
        sessionID: WorktreeAnnotationSessionID,
        expectedSessionRevision: Int,
        expectedProjectionRevision: Int
    ) async throws -> WorktreeAnnotationSessionDetail {
        try requireAvailableForReads()
        guard projectionRevision == expectedProjectionRevision else {
            throw WorktreeAnnotationServiceError.staleSourceEpoch
        }
        let detail = try await repositoryAccess.fetchSessionDetail(sessionID: sessionID)
        guard projectionRevision == expectedProjectionRevision else {
            throw WorktreeAnnotationServiceError.staleSourceEpoch
        }
        guard detail.session.semanticRevision == expectedSessionRevision else {
            throw WorktreeAnnotationRepositoryError.conflict(
                currentRevision: detail.session.semanticRevision
            )
        }
        return detail
    }

    @discardableResult
    func repeatOutputAttempt(
        sourceAttemptID: WorktreeAnnotationOutputAttemptID,
        repeatedAttemptID: WorktreeAnnotationOutputAttemptID,
        destinationPath: String?,
        now: Date
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput {
        try requireMutationAllowed()
        let committed = try await publishCorrelatedMutation(
            worktreeID: { $0.sessionDetail.session.worktreeID },
            {
                try await repositoryAccess.repeatOutputAttempt(
                    sourceAttemptID: sourceAttemptID,
                    repeatedAttemptID: repeatedAttemptID,
                    destinationPath: destinationPath,
                    now: now
                )
            }
        )
        return committed.preparedOutput
    }

    @discardableResult
    func cancelOutputAttempt(
        attemptID: WorktreeAnnotationOutputAttemptID,
        now: Date
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput {
        try requireMutationAllowed()
        let committed = try await publishCorrelatedMutation(
            worktreeID: { $0.sessionDetail.session.worktreeID },
            { try await repositoryAccess.cancelOutputAttempt(attemptID: attemptID, now: now) }
        )
        return committed.preparedOutput
    }

    @discardableResult
    func cancelOutputAttempt(
        attemptID: WorktreeAnnotationOutputAttemptID,
        effectError: String,
        now: Date
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput {
        try requireMutationAllowed()
        let committed = try await publishCorrelatedMutation(
            worktreeID: { $0.sessionDetail.session.worktreeID },
            {
                try await repositoryAccess.cancelOutputAttempt(
                    attemptID: attemptID,
                    effectError: effectError,
                    now: now
                )
            }
        )
        return committed.preparedOutput
    }

    @discardableResult
    func finalizeOutputAttempt(
        attemptID: WorktreeAnnotationOutputAttemptID,
        eventKind: WorktreeAnnotationOutputEventKind,
        now: Date
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput {
        try requireMutationAllowed()
        let committed = try await publishCorrelatedMutation(
            worktreeID: { $0.sessionDetail.session.worktreeID },
            {
                try await repositoryAccess.finalizeOutputAttempt(
                    attemptID: attemptID,
                    eventKind: eventKind,
                    now: now
                )
            }
        )
        return committed.preparedOutput
    }

    @discardableResult
    func markOutputAttemptFinalizationFailed(
        attemptID: WorktreeAnnotationOutputAttemptID,
        cleanupError: String,
        now: Date
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput {
        try requireMutationAllowed()
        let committed = try await publishCorrelatedMutation(
            worktreeID: { $0.sessionDetail.session.worktreeID },
            {
                try await repositoryAccess.markOutputAttemptFinalizationFailed(
                    attemptID: attemptID,
                    cleanupError: cleanupError,
                    now: now
                )
            }
        )
        return committed.preparedOutput
    }

    func fetchOutputHistory(
        sessionID: WorktreeAnnotationSessionID,
        limit: Int
    ) async throws -> [WorktreeAnnotationOutputHistorySummary] {
        try requireAvailableForReads()
        guard limit > 0 else { throw WorktreeAnnotationRepositoryError.invalidState }
        return try await repositoryAccess.fetchOutputHistory(
            sessionID: sessionID,
            limit: min(limit, AppPolicies.Bridge.worktreeAnnotationMaximumOutputHistorySummaries)
        )
    }

    func clearOutputHandled(
        attemptID: WorktreeAnnotationOutputAttemptID,
        expectedSessionRevision: Int,
        now: Date
    ) async throws -> WorktreeAnnotationSessionDetail {
        try await publishCommittedMutation {
            try await repositoryAccess.clearOutputHandled(
                attemptID: attemptID,
                expectedSessionRevision: expectedSessionRevision,
                now: now
            )
        }
    }

    func markPreparedOutputAttemptsUnknown(now: Date) async throws -> Int {
        try requireMutationAllowed()
        let changedCount: Int
        do {
            changedCount = try await repositoryAccess.markPreparedOutputAttemptsUnknown(now: now)
        } catch { throw error }
        if changedCount > 0 {
            activeDemandGenerationByContextKey.removeAll()
        }
        return changedCount
    }

    package func acknowledgeRecovery(at acknowledgedAt: Date) async throws {
        guard let witness = unacknowledgedRecoveryWitness else {
            if recoveryState == .unavailable {
                throw WorktreeAnnotationServiceError.unavailable
            }
            return
        }
        _ = try await repositoryAccess.acknowledgeRecoveryProvenance(
            id: witness.id,
            acknowledgedAt: acknowledgedAt
        )
        unacknowledgedRecoveryWitness = nil
        recoveryState = .available
        await publishSnapshotRequiredForEveryObservedWorktree()
    }

    func requireAvailableForReads() throws {
        if recoveryState == .unavailable {
            throw WorktreeAnnotationServiceError.unavailable
        }
    }

    func requireMutationAllowed() throws {
        try requireAvailableForReads()
        guard unacknowledgedRecoveryWitness == nil else {
            throw WorktreeAnnotationServiceError.recoveryAcknowledgementRequired
        }
    }

    func publishCommittedMutation(
        _ mutation: () async throws -> WorktreeAnnotationSessionDetail
    ) async throws -> WorktreeAnnotationSessionDetail {
        try requireMutationAllowed()
        return try await publishCorrelatedMutation(
            worktreeID: { $0.session.worktreeID },
            mutation
        )
    }

    func publishCorrelatedMutation<CommittedResult: Sendable>(
        worktreeID: (CommittedResult) -> String,
        _ mutation: () async throws -> CommittedResult
    ) async throws -> CommittedResult {
        let operationCorrelationID = BridgeOperationCorrelation.mintScrubbedID()
        await recordNativeAnnotationWork(
            operationCorrelationID: operationCorrelationID,
            result: .started,
            stage: .nativeWorkStarted
        )
        do {
            let committed = try await mutation()
            await recordNativeAnnotationWork(
                operationCorrelationID: operationCorrelationID,
                result: .success,
                stage: .nativeWorkTerminal
            )
            await publishSnapshotRequired(
                worktreeID: worktreeID(committed),
                operationCorrelationID: operationCorrelationID
            )
            return committed
        } catch {
            await recordNativeAnnotationWork(
                operationCorrelationID: operationCorrelationID,
                result: .failure,
                stage: .nativeWorkTerminal
            )
            throw error
        }
    }

    private func rollbackDemandRegistration(
        contextKey: WorktreeAnnotationPlacementContextKey,
        demandGeneration: WorktreeAnnotationDemandGeneration
    ) {
        guard activeDemandGenerationByContextKey[contextKey] == demandGeneration else { return }
        activeDemandGenerationByContextKey.removeValue(forKey: contextKey)
    }

    func publishSnapshotRequired(worktreeID: String, operationCorrelationID: String) async {
        projectionRevision += 1
        let observerTokens =
            changeObserverByToken
            .filter { $0.value.worktreeID == worktreeID }
            .map(\.key)
            .sorted { $0.uuidString < $1.uuidString }
        for (deliveryAttempt, token) in observerTokens.enumerated() {
            guard let observer = changeObserverByToken[token] else {
                continue
            }
            await lifecycleTraceRecorder?.record(
                .init(
                    operationCorrelationID: operationCorrelationID,
                    result: .started,
                    sourceGeneration: projectionRevision,
                    stageAttempt: deliveryAttempt,
                    stage: .notificationDeliveryStarted,
                    surface: nil
                )
            )
            let change = WorktreeAnnotationChange.snapshotRequired(
                worktreeID: worktreeID,
                operationCorrelationID: operationCorrelationID,
                deliveryAttempt: deliveryAttempt
            )
            if case .dropped(let displacedChange) = observer.continuation.yield(change),
                case .snapshotRequired(
                    _,
                    let displacedOperationCorrelationID,
                    let displacedDeliveryAttempt
                ) = displacedChange
            {
                await lifecycleTraceRecorder?.record(
                    .init(
                        operationCorrelationID: displacedOperationCorrelationID,
                        result: .stale,
                        sourceGeneration: projectionRevision,
                        stageAttempt: displacedDeliveryAttempt,
                        stage: .notificationDeliveryTerminal,
                        surface: nil
                    )
                )
            }
        }
    }

    private func publishSnapshotRequiredForEveryObservedWorktree() async {
        projectionRevision += 1
        for worktreeID in Set(changeObserverByToken.values.map(\.worktreeID)) {
            let operationCorrelationID = BridgeOperationCorrelation.mintScrubbedID()
            await recordNativeAnnotationWork(
                operationCorrelationID: operationCorrelationID,
                result: .started,
                stage: .nativeWorkStarted
            )
            await publishSnapshotRequired(
                worktreeID: worktreeID,
                operationCorrelationID: operationCorrelationID
            )
            await recordNativeAnnotationWork(
                operationCorrelationID: operationCorrelationID,
                result: .success,
                stage: .nativeWorkTerminal
            )
        }
    }

    private func recordNativeAnnotationWork(
        operationCorrelationID: String,
        result: BridgeAnnotationLifecycleTraceEvent.Result,
        stage: BridgeAnnotationLifecycleTraceEvent.Stage
    ) async {
        await lifecycleTraceRecorder?.record(
            .init(
                operationCorrelationID: operationCorrelationID,
                result: result,
                sourceGeneration: projectionRevision,
                stage: stage,
                surface: nil
            )
        )
    }

}

extension WorktreeAnnotationServiceActor: WorktreeAnnotationOutputServiceAccess {}
