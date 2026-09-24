import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

enum WorktreeAnnotationChangeDisposition: Equatable, Sendable {
    case content
    case control(WorktreeAnnotationControlChangeReason)
    case catalog
}

/// One change delivered to one observer, keyed by the scope that observer
/// watches.
struct WorktreeAnnotationChange: Equatable, Sendable {
    let scopeKey: String
    let applicationSourceGeneration: Int
    let operationCorrelationID: String
    let deliveryAttempt: Int
    let disposition: WorktreeAnnotationChangeDisposition
    let sessionSemanticRevisionByID: [WorktreeAnnotationSessionID: Int]

    func merging(displaced: Self) -> Self {
        precondition(scopeKey == displaced.scopeKey)
        var mergedSessionSemanticRevisionByID = displaced.sessionSemanticRevisionByID
        for (sessionID, semanticRevision) in sessionSemanticRevisionByID {
            mergedSessionSemanticRevisionByID[sessionID] = max(
                semanticRevision,
                mergedSessionSemanticRevisionByID[sessionID] ?? semanticRevision
            )
        }
        return Self(
            scopeKey: scopeKey,
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
    var scope: WorktreeAnnotationScope
}

extension WorktreeAnnotationServiceActor {
    func registerChangeObserver(scope: WorktreeAnnotationScope) -> WorktreeAnnotationChangeObserver {
        let token = UUIDv7.generate()
        let stream = AsyncStream<WorktreeAnnotationChange>(
            bufferingPolicy: .bufferingNewest(1)
        ) { continuation in
            changeObserverByToken[token] = WorktreeAnnotationChangeObserverState(
                continuation: continuation,
                scope: scope
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
            await publishRecoveryCatalogChange()
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
            await publishRecoveryCatalogChange()
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
        await publishRecoveryControlChange()
    }

    func captureCatalog(
        subjects: Set<WorktreeAnnotationSubject>
    ) async throws -> WorktreeAnnotationServiceCatalogCapture {
        try requireAvailableForReads()
        let capturedGeneration = projectionRevision
        let capturedRecoveryState = recoveryState
        let repositoryCapture = try await repositoryAccess.fetchCatalogCapture(subjects: subjects)
        guard projectionRevision == capturedGeneration,
            recoveryState == capturedRecoveryState,
            repositoryCapture.subjects == subjects
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
        let observerTokens =
            changeObserverByToken
            .filter { observer in publication.subjects.contains { observer.value.scope.subjects.containsKey(of: $0) } }
            .map(\.key)
        await publishChange(
            to: observerTokens,
            applicationSourceGeneration: applicationSourceGeneration,
            operationCorrelationID: operationCorrelationID,
            disposition: publication.disposition,
            sessionChanges: publication.sessionChanges
        )
    }

    /// Replace the subjects every observer of `scope.key` watches, then tell
    /// those observers their catalog changed so they recapture it. A Files
    /// membership or opened-document change arrives here; an unchanged scope
    /// publishes nothing.
    func updateObservedScope(_ scope: WorktreeAnnotationScope) async {
        let affectedTokens = changeObserverByToken.filter {
            $0.value.scope.key == scope.key && $0.value.scope != scope
        }.map(\.key)
        guard !affectedTokens.isEmpty else { return }
        for token in affectedTokens {
            changeObserverByToken[token]?.scope = scope
        }
        let operationCorrelationID = BridgeOperationCorrelation.mintScrubbedID()
        await recordNativeAnnotationWork(
            operationCorrelationID: operationCorrelationID,
            result: .started,
            stage: .nativeWorkStarted
        )
        projectionRevision += 1
        await publishChange(
            to: affectedTokens,
            applicationSourceGeneration: projectionRevision,
            operationCorrelationID: operationCorrelationID,
            disposition: .catalog,
            sessionChanges: []
        )
        await recordNativeAnnotationWork(
            operationCorrelationID: operationCorrelationID,
            result: .success,
            stage: .nativeWorkTerminal
        )
    }

    func publishRecoveryCatalogChange() async {
        await publishRecoveryChangeToEveryObserver(disposition: .catalog)
    }

    func publishRecoveryControlChange() async {
        await publishRecoveryChangeToEveryObserver(disposition: .control(.recovery))
    }

    /// Recovery changes what every surface can read, whatever its scope.
    private func publishRecoveryChangeToEveryObserver(
        disposition: WorktreeAnnotationChangeDisposition
    ) async {
        let operationCorrelationID = BridgeOperationCorrelation.mintScrubbedID()
        await recordNativeAnnotationWork(
            operationCorrelationID: operationCorrelationID,
            result: .started,
            stage: .nativeWorkStarted
        )
        projectionRevision += 1
        await publishChange(
            to: Array(changeObserverByToken.keys),
            applicationSourceGeneration: projectionRevision,
            operationCorrelationID: operationCorrelationID,
            disposition: disposition,
            sessionChanges: []
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
        subjects: Set<WorktreeAnnotationSubject>,
        sessionChanges: [WorktreeAnnotationCommittedSessionChange]
    ) {
        switch committedChange {
        case .noChange:
            preconditionFailure("No-op changes do not publish")
        case .content(let sessionChanges):
            return (
                .content,
                Set(sessionChanges.map(\.subject)),
                sessionChanges
            )
        case .control(let subjects, let reason, let sessionChanges):
            return (
                .control(reason),
                subjects.union(sessionChanges.map(\.subject)),
                sessionChanges
            )
        case .catalog(let subjects, let sessionChanges):
            return (
                .catalog,
                subjects.union(sessionChanges.map(\.subject)),
                sessionChanges
            )
        }
    }

    private static func newestSessionSemanticRevisionByID(
        _ sessionChanges: [WorktreeAnnotationCommittedSessionChange],
        subjects: Set<WorktreeAnnotationSubject>
    ) -> [WorktreeAnnotationSessionID: Int] {
        var newestSemanticRevisionByID: [WorktreeAnnotationSessionID: Int] = [:]
        for sessionChange in sessionChanges where subjects.containsKey(of: sessionChange.subject) {
            newestSemanticRevisionByID[sessionChange.sessionID] = max(
                sessionChange.semanticRevision,
                newestSemanticRevisionByID[sessionChange.sessionID] ?? sessionChange.semanticRevision
            )
        }
        return newestSemanticRevisionByID
    }

    /// Deliver one change to each of `observerTokens`, carrying only the
    /// session revisions inside that observer's scope.
    private func publishChange(
        to observerTokens: [UUID],
        applicationSourceGeneration: Int,
        operationCorrelationID: String,
        disposition: WorktreeAnnotationChangeDisposition,
        sessionChanges: [WorktreeAnnotationCommittedSessionChange]
    ) async {
        let orderedTokens = observerTokens.sorted { $0.uuidString < $1.uuidString }
        for (deliveryAttempt, token) in orderedTokens.enumerated() {
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
                scopeKey: observer.scope.key,
                applicationSourceGeneration: applicationSourceGeneration,
                operationCorrelationID: operationCorrelationID,
                deliveryAttempt: deliveryAttempt,
                disposition: disposition,
                sessionSemanticRevisionByID: Self.newestSessionSemanticRevisionByID(
                    sessionChanges,
                    subjects: observer.scope.subjects
                )
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
