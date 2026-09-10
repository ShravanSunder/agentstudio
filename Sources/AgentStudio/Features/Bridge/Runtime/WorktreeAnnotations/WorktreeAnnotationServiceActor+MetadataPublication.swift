import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

enum WorktreeAnnotationChangeDisposition: Equatable, Sendable {
    case content
    case control(WorktreeAnnotationControlChangeReason)
    case catalog
}

struct WorktreeAnnotationChange: Equatable, Sendable {
    let worktreeID: String
    let applicationSourceGeneration: Int
    let operationCorrelationID: String
    let deliveryAttempt: Int
    let disposition: WorktreeAnnotationChangeDisposition
    let sessionSemanticRevisionByID: [WorktreeAnnotationSessionID: Int]

    func merging(displaced: Self) -> Self {
        precondition(worktreeID == displaced.worktreeID)
        var mergedSessionSemanticRevisionByID = displaced.sessionSemanticRevisionByID
        for (sessionID, semanticRevision) in sessionSemanticRevisionByID {
            mergedSessionSemanticRevisionByID[sessionID] = max(
                semanticRevision,
                mergedSessionSemanticRevisionByID[sessionID] ?? semanticRevision
            )
        }
        return Self(
            worktreeID: worktreeID,
            applicationSourceGeneration: max(
                applicationSourceGeneration,
                displaced.applicationSourceGeneration
            ),
            operationCorrelationID: operationCorrelationID,
            deliveryAttempt: deliveryAttempt,
            disposition: disposition.merging(displaced: displaced.disposition),
            sessionSemanticRevisionByID: mergedSessionSemanticRevisionByID
        )
    }
}

extension WorktreeAnnotationChangeDisposition {
    fileprivate func merging(displaced: Self) -> Self {
        switch (self, displaced) {
        case (.catalog, _), (_, .catalog):
            return .catalog
        case (.control(let reason), _):
            return .control(reason)
        case (.content, .control(let reason)):
            return .control(reason)
        case (.content, .content):
            return .content
        }
    }
}

struct WorktreeAnnotationServiceCatalogCapture: Equatable, Sendable {
    let applicationSourceGeneration: Int
    let recoveryState: WorktreeAnnotationRecoveryState
    let repositoryCapture: WorktreeAnnotationCatalogCapture
}

struct WorktreeAnnotationChangeObserver: Sendable {
    let stream: AsyncStream<WorktreeAnnotationChange>
    let token: UUID
}

struct WorktreeAnnotationChangeObserverState {
    let continuation: AsyncStream<WorktreeAnnotationChange>.Continuation
    let worktreeID: String
}

extension WorktreeAnnotationServiceActor {
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
            await publishRecoveryCatalogChangeForObservedWorktrees()
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
            await publishRecoveryCatalogChangeForObservedWorktrees()
            return PersistenceRecoveryEvent(
                store: .worktreeAnnotations,
                workspaceId: nil,
                recovery: .resetToDefaults
            )
        }
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
        await publishRecoveryControlChangeForObservedWorktrees()
    }

    func captureCatalog(worktreeID: String) async throws -> WorktreeAnnotationServiceCatalogCapture {
        try requireAvailableForReads()
        let capturedGeneration = projectionRevision
        let capturedRecoveryState = recoveryState
        let repositoryCapture = try await repositoryAccess.fetchCatalogCapture(worktreeID: worktreeID)
        guard projectionRevision == capturedGeneration,
            recoveryState == capturedRecoveryState,
            repositoryCapture.worktreeID == worktreeID
        else {
            throw WorktreeAnnotationServiceError.staleSourceEpoch
        }
        return WorktreeAnnotationServiceCatalogCapture(
            applicationSourceGeneration: capturedGeneration,
            recoveryState: capturedRecoveryState,
            repositoryCapture: repositoryCapture
        )
    }

    func applyCommittedChange(
        _ committedChange: WorktreeAnnotationCommittedChange,
        operationCorrelationID: String
    ) async {
        guard committedChange != .noChange else { return }
        projectionRevision += 1
        let applicationSourceGeneration = projectionRevision
        let publication = Self.publicationComponents(for: committedChange)
        for worktreeID in publication.worktreeIDs.sorted() {
            await publishChange(
                worktreeID: worktreeID,
                applicationSourceGeneration: applicationSourceGeneration,
                operationCorrelationID: operationCorrelationID,
                disposition: publication.disposition,
                sessionSemanticRevisionByID: Self.newestSessionSemanticRevisionByID(
                    publication.sessionChanges,
                    worktreeID: worktreeID
                )
            )
        }
    }

    func publishRecoveryCatalogChangeForObservedWorktrees() async {
        let observedWorktreeIDs = Set(changeObserverByToken.values.map(\.worktreeID))
        let operationCorrelationID = BridgeOperationCorrelation.mintScrubbedID()
        await recordNativeAnnotationWork(
            operationCorrelationID: operationCorrelationID,
            result: .started,
            stage: .nativeWorkStarted
        )
        await applyCommittedChange(
            .catalog(worktreeIDs: observedWorktreeIDs, sessionChanges: []),
            operationCorrelationID: operationCorrelationID
        )
        await recordNativeAnnotationWork(
            operationCorrelationID: operationCorrelationID,
            result: .success,
            stage: .nativeWorkTerminal
        )
    }

    func publishRecoveryControlChangeForObservedWorktrees() async {
        let observedWorktreeIDs = Set(changeObserverByToken.values.map(\.worktreeID))
        let operationCorrelationID = BridgeOperationCorrelation.mintScrubbedID()
        await recordNativeAnnotationWork(
            operationCorrelationID: operationCorrelationID,
            result: .started,
            stage: .nativeWorkStarted
        )
        await applyCommittedChange(
            .control(
                worktreeIDs: observedWorktreeIDs,
                reason: .recovery,
                sessionChanges: []
            ),
            operationCorrelationID: operationCorrelationID
        )
        await recordNativeAnnotationWork(
            operationCorrelationID: operationCorrelationID,
            result: .success,
            stage: .nativeWorkTerminal
        )
    }

    private static func publicationComponents(
        for committedChange: WorktreeAnnotationCommittedChange
    ) -> (
        disposition: WorktreeAnnotationChangeDisposition,
        worktreeIDs: Set<String>,
        sessionChanges: [WorktreeAnnotationCommittedSessionChange]
    ) {
        switch committedChange {
        case .noChange:
            preconditionFailure("No-op changes do not publish")
        case .content(let sessionChanges):
            return (
                .content,
                Set(sessionChanges.map(\.worktreeID)),
                sessionChanges
            )
        case .control(let worktreeIDs, let reason, let sessionChanges):
            return (
                .control(reason),
                worktreeIDs.union(sessionChanges.map(\.worktreeID)),
                sessionChanges
            )
        case .catalog(let worktreeIDs, let sessionChanges):
            return (
                .catalog,
                worktreeIDs.union(sessionChanges.map(\.worktreeID)),
                sessionChanges
            )
        }
    }

    private static func newestSessionSemanticRevisionByID(
        _ sessionChanges: [WorktreeAnnotationCommittedSessionChange],
        worktreeID: String
    ) -> [WorktreeAnnotationSessionID: Int] {
        var newestSemanticRevisionByID: [WorktreeAnnotationSessionID: Int] = [:]
        for sessionChange in sessionChanges where sessionChange.worktreeID == worktreeID {
            newestSemanticRevisionByID[sessionChange.sessionID] = max(
                sessionChange.semanticRevision,
                newestSemanticRevisionByID[sessionChange.sessionID] ?? sessionChange.semanticRevision
            )
        }
        return newestSemanticRevisionByID
    }

    private func publishChange(
        worktreeID: String,
        applicationSourceGeneration: Int,
        operationCorrelationID: String,
        disposition: WorktreeAnnotationChangeDisposition,
        sessionSemanticRevisionByID: [WorktreeAnnotationSessionID: Int]
    ) async {
        let observerTokens =
            changeObserverByToken
            .filter { $0.value.worktreeID == worktreeID }
            .map(\.key)
            .sorted { $0.uuidString < $1.uuidString }
        for (deliveryAttempt, token) in observerTokens.enumerated() {
            guard let observer = changeObserverByToken[token] else { continue }
            await lifecycleTraceRecorder?.record(
                .init(
                    operationCorrelationID: operationCorrelationID,
                    result: .started,
                    sourceGeneration: applicationSourceGeneration,
                    stageAttempt: deliveryAttempt,
                    stage: .notificationDeliveryStarted,
                    surface: nil
                )
            )
            let change = WorktreeAnnotationChange(
                worktreeID: worktreeID,
                applicationSourceGeneration: applicationSourceGeneration,
                operationCorrelationID: operationCorrelationID,
                deliveryAttempt: deliveryAttempt,
                disposition: disposition,
                sessionSemanticRevisionByID: sessionSemanticRevisionByID
            )
            if case .dropped(let displacedChange) = observer.continuation.yield(change) {
                _ = observer.continuation.yield(change.merging(displaced: displacedChange))
                await lifecycleTraceRecorder?.record(
                    .init(
                        operationCorrelationID: displacedChange.operationCorrelationID,
                        result: .stale,
                        sourceGeneration: displacedChange.applicationSourceGeneration,
                        stageAttempt: displacedChange.deliveryAttempt,
                        stage: .notificationDeliveryTerminal,
                        surface: nil
                    )
                )
            }
        }
    }
}
