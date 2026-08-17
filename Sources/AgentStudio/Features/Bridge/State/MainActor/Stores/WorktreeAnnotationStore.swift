import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

enum WorktreeAnnotationStoreError: Error, Equatable, Sendable {
    case recoveryAcknowledgementRequired
    case staleSourceEpoch
    case unavailable
}

private struct WorktreeAnnotationDemandKey: Hashable {
    let worktreeID: String
    let sessionID: WorktreeAnnotationSessionID
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

struct WorktreeAnnotationOutputSnapshotContext: Sendable {
    let sessionDetail: WorktreeAnnotationSessionDetail
    let placementsByThreadID: [WorktreeAnnotationThreadID: WorktreeAnnotationThreadPlacementProjection]
}

/// Application-scoped coordinator for annotation commands, queries, and demand.
///
/// Semantic mutations always await the repository transaction and only then
/// publish its committed detail into the projection Atom.
@MainActor
package final class WorktreeAnnotationStore {
    package let projection: WorktreeAnnotationProjectionAtom
    private let repositoryAccess: any WorktreeAnnotationRepositoryAccess
    private var demandCountByKey: [WorktreeAnnotationDemandKey: Int] = [:]
    private var activeDemandGenerationByContextKey:
        [WorktreeAnnotationPlacementContextKey: WorktreeAnnotationDemandGeneration] = [:]
    private var latestSourceRefreshFenceByContextKey:
        [WorktreeAnnotationPlacementContextKey: WorktreeAnnotationSourceRefreshFence] = [:]
    private var unacknowledgedRecoveryWitness: WorktreeAnnotationRecoveryProvenance?

    init(
        projection: WorktreeAnnotationProjectionAtom,
        repositoryAccess: any WorktreeAnnotationRepositoryAccess
    ) {
        self.projection = projection
        self.repositoryAccess = repositoryAccess
    }

    package convenience init(
        projection: WorktreeAnnotationProjectionAtom,
        sqliteAdapter: WorktreeAnnotationSQLiteDatastoreAdapter
    ) {
        self.init(projection: projection, repositoryAccess: sqliteAdapter)
    }

    @discardableResult
    package func restoreRecoveryState() async -> PersistenceRecoveryEvent? {
        do {
            let witness = try await repositoryAccess.fetchUnacknowledgedRecoveryProvenance()
            unacknowledgedRecoveryWitness = witness
            projection.publishRecoveryState(
                witness.map(WorktreeAnnotationRecoveryState.recoveredDegraded) ?? .available)
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
            projection.publishRecoveryState(.unavailable)
            return PersistenceRecoveryEvent(
                store: .worktreeAnnotations,
                workspaceId: nil,
                recovery: .resetToDefaults
            )
        }
    }

    func discoverSessions(worktreeID: String) async throws -> [WorktreeAnnotationSession] {
        try requireAvailableForReads()
        let sessions = try await repositoryAccess.discoverSessions(worktreeID: worktreeID)
        projection.publishDiscovery(sessions, worktreeID: worktreeID)
        return sessions
    }

    func acquireDemand(
        worktreeID: String,
        contextID: String,
        surface: BridgeProductSurface,
        sessionID: WorktreeAnnotationSessionID
    ) async throws -> WorktreeAnnotationDemandGeneration {
        try requireAvailableForReads()
        guard !contextID.isEmpty else { throw WorktreeAnnotationStoreError.staleSourceEpoch }

        let contextKey = WorktreeAnnotationPlacementContextKey(
            contextID: contextID,
            surface: surface,
            sessionID: sessionID
        )
        let demandGeneration = WorktreeAnnotationDemandGeneration(id: UUIDv7.generate())
        let replacedDemandGeneration = activeDemandGenerationByContextKey.updateValue(
            demandGeneration,
            forKey: contextKey
        )
        let key = WorktreeAnnotationDemandKey(worktreeID: worktreeID, sessionID: sessionID)
        if replacedDemandGeneration == nil {
            demandCountByKey[key] = (demandCountByKey[key] ?? 0) + 1
        }
        if let publishedDetail = projection.detail(sessionID: sessionID) {
            guard publishedDetail.session.worktreeID == worktreeID else {
                rollbackDemandRegistration(
                    key: key,
                    contextKey: contextKey,
                    demandGeneration: demandGeneration
                )
                throw WorktreeAnnotationRepositoryError.notFound
            }
            return demandGeneration
        }
        let detail: WorktreeAnnotationSessionDetail
        do {
            detail = try await repositoryAccess.fetchSessionDetail(sessionID: sessionID)
        } catch {
            rollbackDemandRegistration(
                key: key,
                contextKey: contextKey,
                demandGeneration: demandGeneration
            )
            projection.publishRecoveryState(.unavailable)
            throw error
        }
        guard activeDemandGenerationByContextKey[contextKey] == demandGeneration else {
            throw WorktreeAnnotationStoreError.staleSourceEpoch
        }
        guard detail.session.worktreeID == worktreeID else {
            rollbackDemandRegistration(
                key: key,
                contextKey: contextKey,
                demandGeneration: demandGeneration
            )
            throw WorktreeAnnotationRepositoryError.notFound
        }
        projection.publish(detail: detail)
        return demandGeneration
    }

    func releaseDemand(
        worktreeID: String,
        contextID: String,
        surface: BridgeProductSurface,
        sessionID: WorktreeAnnotationSessionID
    ) {
        let contextKey = WorktreeAnnotationPlacementContextKey(
            contextID: contextID,
            surface: surface,
            sessionID: sessionID
        )
        guard activeDemandGenerationByContextKey.removeValue(forKey: contextKey) != nil else {
            return
        }

        let key = WorktreeAnnotationDemandKey(worktreeID: worktreeID, sessionID: sessionID)
        guard let currentCount = demandCountByKey[key] else { return }
        if currentCount > 1 {
            demandCountByKey[key] = currentCount - 1
            return
        }
        demandCountByKey.removeValue(forKey: key)
        projection.evictDetail(sessionID: sessionID)
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
        let committedDetail = try await repositoryAccess.createRootDraft(props)
        projection.publish(detail: committedDetail)
        return committedDetail
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
        guard !props.contextID.isEmpty, props.sourceEpoch >= 0 else {
            throw WorktreeAnnotationStoreError.staleSourceEpoch
        }
        let contextKey = WorktreeAnnotationPlacementContextKey(
            contextID: props.contextID,
            surface: props.surface,
            sessionID: props.sessionID
        )
        guard activeDemandGenerationByContextKey[contextKey] == props.demandGeneration else {
            throw WorktreeAnnotationStoreError.staleSourceEpoch
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
                throw WorktreeAnnotationStoreError.staleSourceEpoch
            }
        }
        latestSourceRefreshFenceByContextKey[contextKey] = refreshFence

        let loadedDetail = try await repositoryAccess.fetchSessionDetail(sessionID: props.sessionID)
        guard activeDemandGenerationByContextKey[contextKey] == props.demandGeneration,
            latestSourceRefreshFenceByContextKey[contextKey] == refreshFence
        else {
            throw WorktreeAnnotationStoreError.staleSourceEpoch
        }
        guard Self.sourceRefreshSnapshot(from: loadedDetail) == props.expectedSnapshot else {
            throw WorktreeAnnotationStoreError.staleSourceEpoch
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
            throw WorktreeAnnotationStoreError.staleSourceEpoch
        }
        projection.publish(
            detail: committedDetail,
            sourceEvaluation: evaluation,
            contextID: props.contextID,
            surface: props.surface,
            sourceEpoch: props.sourceEpoch
        )
        return committedDetail
    }

    @discardableResult
    func prepareOutput(
        _ props: WorktreeAnnotationSQLiteRepository.PrepareOutputProps
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput {
        try requireMutationAllowed()
        let committed = try await repositoryAccess.prepareOutput(props)
        projection.publish(detail: committed.sessionDetail)
        return committed.preparedOutput
    }

    func inspectOutputAttempt(
        attemptID: WorktreeAnnotationOutputAttemptID
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput {
        try requireAvailableForReads()
        return try await repositoryAccess.inspectOutputAttempt(attemptID: attemptID)
    }

    func outputSnapshotContext(
        sessionID: WorktreeAnnotationSessionID,
        contextID: String,
        surface: BridgeProductSurface
    ) async throws -> WorktreeAnnotationOutputSnapshotContext {
        try requireAvailableForReads()
        let detail = try await repositoryAccess.fetchSessionDetail(sessionID: sessionID)
        return WorktreeAnnotationOutputSnapshotContext(
            sessionDetail: detail,
            placementsByThreadID: projection.placements(
                contextID: contextID,
                surface: surface,
                sessionID: sessionID
            )
        )
    }

    @discardableResult
    func repeatOutputAttempt(
        sourceAttemptID: WorktreeAnnotationOutputAttemptID,
        repeatedAttemptID: WorktreeAnnotationOutputAttemptID,
        destinationPath: String?,
        now: Date
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput {
        try requireMutationAllowed()
        let committed = try await repositoryAccess.repeatOutputAttempt(
            sourceAttemptID: sourceAttemptID,
            repeatedAttemptID: repeatedAttemptID,
            destinationPath: destinationPath,
            now: now
        )
        projection.publish(detail: committed.sessionDetail)
        return committed.preparedOutput
    }

    @discardableResult
    func cancelOutputAttempt(
        attemptID: WorktreeAnnotationOutputAttemptID,
        now: Date
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput {
        try requireMutationAllowed()
        let committed = try await repositoryAccess.cancelOutputAttempt(
            attemptID: attemptID,
            now: now
        )
        projection.publish(detail: committed.sessionDetail)
        return committed.preparedOutput
    }

    @discardableResult
    func cancelOutputAttempt(
        attemptID: WorktreeAnnotationOutputAttemptID,
        effectError: String,
        now: Date
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput {
        try requireMutationAllowed()
        let committed = try await repositoryAccess.cancelOutputAttempt(
            attemptID: attemptID,
            effectError: effectError,
            now: now
        )
        projection.publish(detail: committed.sessionDetail)
        return committed.preparedOutput
    }

    @discardableResult
    func finalizeOutputAttempt(
        attemptID: WorktreeAnnotationOutputAttemptID,
        eventKind: WorktreeAnnotationOutputEventKind,
        now: Date
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput {
        try requireMutationAllowed()
        let committed = try await repositoryAccess.finalizeOutputAttempt(
            attemptID: attemptID,
            eventKind: eventKind,
            now: now
        )
        projection.publish(detail: committed.sessionDetail)
        return committed.preparedOutput
    }

    @discardableResult
    func markOutputAttemptFinalizationFailed(
        attemptID: WorktreeAnnotationOutputAttemptID,
        cleanupError: String,
        now: Date
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput {
        try requireMutationAllowed()
        let committed = try await repositoryAccess.markOutputAttemptFinalizationFailed(
            attemptID: attemptID,
            cleanupError: cleanupError,
            now: now
        )
        projection.publish(detail: committed.sessionDetail)
        return committed.preparedOutput
    }

    func fetchOutputHistory(
        sessionID: WorktreeAnnotationSessionID,
        limit: Int
    ) async throws -> [WorktreeAnnotationOutputHistorySummary] {
        try requireAvailableForReads()
        guard limit > 0 else { throw WorktreeAnnotationRepositoryError.invalidState }
        let history = try await repositoryAccess.fetchOutputHistory(
            sessionID: sessionID,
            limit: min(limit, AppPolicies.Bridge.worktreeAnnotationMaximumOutputHistorySummaries)
        )
        projection.publish(outputHistory: history, sessionID: sessionID)
        return history
    }

    func markPreparedOutputAttemptsUnknown(now: Date) async throws -> Int {
        try requireMutationAllowed()
        let changedCount = try await repositoryAccess.markPreparedOutputAttemptsUnknown(now: now)
        if changedCount > 0 {
            projection.evictAllDetails()
            demandCountByKey.removeAll()
            activeDemandGenerationByContextKey.removeAll()
        }
        return changedCount
    }

    package func acknowledgeRecovery(at acknowledgedAt: Date) async throws {
        guard let witness = unacknowledgedRecoveryWitness else {
            if projection.recoveryState == .unavailable {
                throw WorktreeAnnotationStoreError.unavailable
            }
            return
        }
        _ = try await repositoryAccess.acknowledgeRecoveryProvenance(
            id: witness.id,
            acknowledgedAt: acknowledgedAt
        )
        unacknowledgedRecoveryWitness = nil
        projection.publishRecoveryState(.available)
    }

    private func requireAvailableForReads() throws {
        if projection.recoveryState == .unavailable {
            throw WorktreeAnnotationStoreError.unavailable
        }
    }

    private func requireMutationAllowed() throws {
        try requireAvailableForReads()
        guard unacknowledgedRecoveryWitness == nil else {
            throw WorktreeAnnotationStoreError.recoveryAcknowledgementRequired
        }
    }

    private func publishCommittedMutation(
        _ mutation: () async throws -> WorktreeAnnotationSessionDetail
    ) async throws -> WorktreeAnnotationSessionDetail {
        try requireMutationAllowed()
        let committedDetail = try await mutation()
        projection.publish(detail: committedDetail)
        return committedDetail
    }

    private func rollbackDemandRegistration(
        key: WorktreeAnnotationDemandKey,
        contextKey: WorktreeAnnotationPlacementContextKey,
        demandGeneration: WorktreeAnnotationDemandGeneration
    ) {
        guard activeDemandGenerationByContextKey[contextKey] == demandGeneration else { return }
        activeDemandGenerationByContextKey.removeValue(forKey: contextKey)
        if let currentCount = demandCountByKey[key] {
            if currentCount > 1 {
                demandCountByKey[key] = currentCount - 1
            } else {
                demandCountByKey.removeValue(forKey: key)
            }
        }
    }

    private static func sourceRefreshSnapshot(
        from detail: WorktreeAnnotationSessionDetail
    ) -> WorktreeAnnotationSourceRefreshSnapshot {
        let orderedThreads = detail.threads.sorted { left, right in
            if left.thread.createdOrdinal != right.thread.createdOrdinal {
                return left.thread.createdOrdinal < right.thread.createdOrdinal
            }
            return left.thread.id.rawValue.uuidString < right.thread.id.rawValue.uuidString
        }
        return WorktreeAnnotationSourceRefreshSnapshot(
            sessionID: detail.session.id,
            acceptedSourceFingerprint: detail.session.acceptedSourceFingerprint,
            requirements: orderedThreads.map {
                WorktreeAnnotationSourceRefreshRequirement(
                    threadID: $0.thread.id,
                    origin: $0.thread.origin
                )
            }
        )
    }
}

extension WorktreeAnnotationStore: WorktreeAnnotationOutputStoreAccess {}
