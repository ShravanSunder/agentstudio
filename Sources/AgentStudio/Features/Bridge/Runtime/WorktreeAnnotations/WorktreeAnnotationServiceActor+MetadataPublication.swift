import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

enum WorktreeAnnotationChangeDisposition: Equatable, Sendable {
    case content
    case control(WorktreeAnnotationControlChangeReason)
    case catalog
}

struct WorktreeAnnotationChange: Equatable, Sendable {
    let subject: WorktreeAnnotationSubject
    let applicationSourceGeneration: Int
    let operationCorrelationID: String
    let deliveryAttempt: Int
    let disposition: WorktreeAnnotationChangeDisposition
    let sessionSemanticRevisionByID: [WorktreeAnnotationSessionID: Int]

    func merging(displaced: Self) -> Self {
        precondition(subject == displaced.subject)
        var mergedSessionSemanticRevisionByID = displaced.sessionSemanticRevisionByID
        for (sessionID, semanticRevision) in sessionSemanticRevisionByID {
            mergedSessionSemanticRevisionByID[sessionID] = max(
                semanticRevision,
                mergedSessionSemanticRevisionByID[sessionID] ?? semanticRevision
            )
        }
        return Self(
            subject: subject,
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
    let subject: WorktreeAnnotationSubject
}

extension WorktreeAnnotationServiceActor {
    func registerChangeObserver(subject: WorktreeAnnotationSubject) -> WorktreeAnnotationChangeObserver {
        let token = UUIDv7.generate()
        let stream = AsyncStream<WorktreeAnnotationChange>(
            bufferingPolicy: .bufferingNewest(1)
        ) { continuation in
            changeObserverByToken[token] = WorktreeAnnotationChangeObserverState(
                continuation: continuation,
                subject: subject
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
            await publishRecoveryCatalogChangeForObservedSubjects()
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
            await publishRecoveryCatalogChangeForObservedSubjects()
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
        await publishRecoveryControlChangeForObservedSubjects()
    }

    func captureCatalog(subject: WorktreeAnnotationSubject) async throws -> WorktreeAnnotationServiceCatalogCapture {
        try requireAvailableForReads()
        let capturedGeneration = projectionRevision
        let capturedRecoveryState = recoveryState
        let repositoryCapture = try await repositoryAccess.fetchCatalogCapture(subject: subject)
        guard projectionRevision == capturedGeneration,
            recoveryState == capturedRecoveryState,
            repositoryCapture.subject == subject
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
        for subject in publication.subjects.sorted() {
            await publishChange(
                subject: subject,
                applicationSourceGeneration: applicationSourceGeneration,
                operationCorrelationID: operationCorrelationID,
                disposition: publication.disposition,
                sessionSemanticRevisionByID: Self.newestSessionSemanticRevisionByID(
                    publication.sessionChanges,
                    subject: subject
                )
            )
        }
    }

    func publishRecoveryCatalogChangeForObservedSubjects() async {
        let observedSubjects = Set(changeObserverByToken.values.map(\.subject))
        let operationCorrelationID = BridgeOperationCorrelation.mintScrubbedID()
        await recordNativeAnnotationWork(
            operationCorrelationID: operationCorrelationID,
            result: .started,
            stage: .nativeWorkStarted
        )
        await applyCommittedChange(
            .catalog(subjects: observedSubjects, sessionChanges: []),
            operationCorrelationID: operationCorrelationID
        )
        await recordNativeAnnotationWork(
            operationCorrelationID: operationCorrelationID,
            result: .success,
            stage: .nativeWorkTerminal
        )
    }

    func publishRecoveryControlChangeForObservedSubjects() async {
        let observedSubjects = Set(changeObserverByToken.values.map(\.subject))
        let operationCorrelationID = BridgeOperationCorrelation.mintScrubbedID()
        await recordNativeAnnotationWork(
            operationCorrelationID: operationCorrelationID,
            result: .started,
            stage: .nativeWorkStarted
        )
        await applyCommittedChange(
            .control(
                subjects: observedSubjects,
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
        subject: WorktreeAnnotationSubject
    ) -> [WorktreeAnnotationSessionID: Int] {
        var newestSemanticRevisionByID: [WorktreeAnnotationSessionID: Int] = [:]
        for sessionChange in sessionChanges where sessionChange.subject == subject {
            newestSemanticRevisionByID[sessionChange.sessionID] = max(
                sessionChange.semanticRevision,
                newestSemanticRevisionByID[sessionChange.sessionID] ?? sessionChange.semanticRevision
            )
        }
        return newestSemanticRevisionByID
    }

    private func publishChange(
        subject: WorktreeAnnotationSubject,
        applicationSourceGeneration: Int,
        operationCorrelationID: String,
        disposition: WorktreeAnnotationChangeDisposition,
        sessionSemanticRevisionByID: [WorktreeAnnotationSessionID: Int]
    ) async {
        let observerTokens =
            changeObserverByToken
            .filter { $0.value.subject == subject }
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
                subject: subject,
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
