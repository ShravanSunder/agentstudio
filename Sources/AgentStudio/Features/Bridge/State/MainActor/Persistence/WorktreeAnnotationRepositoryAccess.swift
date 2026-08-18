import AgentStudioCore
import Foundation

protocol WorktreeAnnotationRepositoryAccess: Sendable {
    func discoverSessions(worktreeID: String) async throws -> [WorktreeAnnotationSession]
    func fetchSessionDetail(sessionID: WorktreeAnnotationSessionID) async throws
        -> WorktreeAnnotationSessionDetail
    func createRootDraft(_ props: WorktreeAnnotationSQLiteRepository.CreateRootDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    func flushDraft(_ props: WorktreeAnnotationSQLiteRepository.FlushDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    func saveDraft(_ props: WorktreeAnnotationSQLiteRepository.SaveDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    func revertDraft(_ props: WorktreeAnnotationSQLiteRepository.RevertDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    func acquireEditToken(_ props: WorktreeAnnotationSQLiteRepository.AcquireEditTokenProps) async throws
        -> WorktreeAnnotationSessionDetail
    func releaseEditToken(_ props: WorktreeAnnotationSQLiteRepository.ReleaseEditTokenProps) async throws
        -> WorktreeAnnotationSessionDetail
    func createReplyDraft(_ props: WorktreeAnnotationSQLiteRepository.CreateReplyDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    func setThreadResolution(_ props: WorktreeAnnotationSQLiteRepository.SetThreadResolutionProps) async throws
        -> WorktreeAnnotationSessionDetail
    func setSessionLifecycle(_ props: WorktreeAnnotationSQLiteRepository.SetSessionLifecycleProps) async throws
        -> WorktreeAnnotationSessionDetail
    func setSourceRelationship(_ props: WorktreeAnnotationSQLiteRepository.SetSourceRelationshipProps) async throws
        -> WorktreeAnnotationSessionDetail
    func prepareOutput(_ props: WorktreeAnnotationSQLiteRepository.PrepareOutputProps) async throws
        -> WorktreeAnnotationOutputMutationResult
    func inspectOutputAttempt(attemptID: WorktreeAnnotationOutputAttemptID) async throws
        -> WorktreeAnnotationSQLiteRepository.PreparedOutput
    func repeatOutputAttempt(
        sourceAttemptID: WorktreeAnnotationOutputAttemptID,
        repeatedAttemptID: WorktreeAnnotationOutputAttemptID,
        destinationPath: String?,
        now: Date
    ) async throws -> WorktreeAnnotationOutputMutationResult
    func cancelOutputAttempt(attemptID: WorktreeAnnotationOutputAttemptID, now: Date) async throws
        -> WorktreeAnnotationOutputMutationResult
    func cancelOutputAttempt(
        attemptID: WorktreeAnnotationOutputAttemptID,
        effectError: String,
        now: Date
    ) async throws -> WorktreeAnnotationOutputMutationResult
    func finalizeOutputAttempt(
        attemptID: WorktreeAnnotationOutputAttemptID,
        eventKind: WorktreeAnnotationOutputEventKind,
        now: Date
    ) async throws -> WorktreeAnnotationOutputMutationResult
    func markOutputAttemptFinalizationFailed(
        attemptID: WorktreeAnnotationOutputAttemptID,
        cleanupError: String,
        now: Date
    ) async throws -> WorktreeAnnotationOutputMutationResult
    func fetchOutputHistory(
        sessionID: WorktreeAnnotationSessionID,
        limit: Int
    ) async throws -> [WorktreeAnnotationOutputHistorySummary]
    func fetchOutputCandidates(
        sessionID: WorktreeAnnotationSessionID,
        expectedSessionRevision: Int,
        cursor: WorktreeAnnotationOutputCandidateCursor?,
        limit: Int
    ) async throws -> WorktreeAnnotationRepositoryOutputCandidatePage
    func markPreparedOutputAttemptsUnknown(now: Date) async throws -> Int
    func fetchUnacknowledgedRecoveryProvenance() async throws
        -> WorktreeAnnotationRecoveryProvenance?
    func acknowledgeRecoveryProvenance(
        id: WorktreeAnnotationRecoveryProvenanceID,
        acknowledgedAt: Date
    ) async throws -> WorktreeAnnotationRecoveryProvenance
}

extension WorktreeAnnotationRepositoryAccess {
    func acquireEditToken(_ props: WorktreeAnnotationSQLiteRepository.AcquireEditTokenProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        _ = props
        throw WorktreeAnnotationRepositoryError.invalidState
    }

    func releaseEditToken(_ props: WorktreeAnnotationSQLiteRepository.ReleaseEditTokenProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        _ = props
        throw WorktreeAnnotationRepositoryError.invalidState
    }

    func repeatOutputAttempt(
        sourceAttemptID: WorktreeAnnotationOutputAttemptID,
        repeatedAttemptID: WorktreeAnnotationOutputAttemptID,
        destinationPath: String?,
        now: Date
    ) async throws -> WorktreeAnnotationOutputMutationResult {
        _ = (sourceAttemptID, repeatedAttemptID, destinationPath, now)
        throw WorktreeAnnotationRepositoryError.invalidState
    }

    func cancelOutputAttempt(
        attemptID: WorktreeAnnotationOutputAttemptID,
        effectError: String,
        now: Date
    ) async throws -> WorktreeAnnotationOutputMutationResult {
        _ = effectError
        return try await cancelOutputAttempt(attemptID: attemptID, now: now)
    }

    func markOutputAttemptFinalizationFailed(
        attemptID: WorktreeAnnotationOutputAttemptID,
        cleanupError: String,
        now: Date
    ) async throws -> WorktreeAnnotationOutputMutationResult {
        _ = (attemptID, cleanupError, now)
        throw WorktreeAnnotationRepositoryError.invalidState
    }

    func fetchOutputHistory(
        sessionID: WorktreeAnnotationSessionID,
        limit: Int
    ) async throws -> [WorktreeAnnotationOutputHistorySummary] {
        _ = (sessionID, limit)
        throw WorktreeAnnotationRepositoryError.invalidState
    }

    func fetchOutputCandidates(
        sessionID: WorktreeAnnotationSessionID,
        expectedSessionRevision: Int,
        cursor: WorktreeAnnotationOutputCandidateCursor?,
        limit: Int
    ) async throws -> WorktreeAnnotationRepositoryOutputCandidatePage {
        _ = (sessionID, expectedSessionRevision, cursor, limit)
        throw WorktreeAnnotationRepositoryError.invalidState
    }
}

struct WorktreeAnnotationOutputMutationResult: Equatable, Sendable {
    let preparedOutput: WorktreeAnnotationSQLiteRepository.PreparedOutput
    let sessionDetail: WorktreeAnnotationSessionDetail
}

package struct WorktreeAnnotationSQLiteDatastoreAdapter: WorktreeAnnotationRepositoryAccess {
    package let workspaceID: UUID
    package let datastore: WorkspaceSQLiteDatastore

    package init(workspaceID: UUID, datastore: WorkspaceSQLiteDatastore) {
        self.workspaceID = workspaceID
        self.datastore = datastore
    }

    func discoverSessions(worktreeID: String) async throws -> [WorktreeAnnotationSession] {
        try await restore { try $0.discoverSessions(worktreeID: worktreeID) }
    }

    func fetchSessionDetail(sessionID: WorktreeAnnotationSessionID) async throws
        -> WorktreeAnnotationSessionDetail
    {
        try await restore { try $0.fetchSessionDetail(sessionID: sessionID) }
    }

    func createRootDraft(_ props: WorktreeAnnotationSQLiteRepository.CreateRootDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        try await mutate { try $0.createRootDraft(props) }
    }

    func flushDraft(_ props: WorktreeAnnotationSQLiteRepository.FlushDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        try await mutate { try $0.flushDraft(props) }
    }

    func saveDraft(_ props: WorktreeAnnotationSQLiteRepository.SaveDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        try await mutate { try $0.saveDraft(props) }
    }

    func revertDraft(_ props: WorktreeAnnotationSQLiteRepository.RevertDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        try await mutate { try $0.revertDraft(props) }
    }

    func acquireEditToken(_ props: WorktreeAnnotationSQLiteRepository.AcquireEditTokenProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        try await mutate { try $0.acquireEditToken(props) }
    }

    func releaseEditToken(_ props: WorktreeAnnotationSQLiteRepository.ReleaseEditTokenProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        try await mutate { try $0.releaseEditToken(props) }
    }

    func createReplyDraft(_ props: WorktreeAnnotationSQLiteRepository.CreateReplyDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        try await mutate { try $0.createReplyDraft(props) }
    }

    func setThreadResolution(_ props: WorktreeAnnotationSQLiteRepository.SetThreadResolutionProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        try await mutate { try $0.setThreadResolution(props) }
    }

    func setSessionLifecycle(_ props: WorktreeAnnotationSQLiteRepository.SetSessionLifecycleProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        try await mutate { try $0.setSessionLifecycle(props) }
    }

    func setSourceRelationship(_ props: WorktreeAnnotationSQLiteRepository.SetSourceRelationshipProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        try await mutate { try $0.setSourceRelationship(props) }
    }

    func prepareOutput(_ props: WorktreeAnnotationSQLiteRepository.PrepareOutputProps) async throws
        -> WorktreeAnnotationOutputMutationResult
    {
        try await mutate { repository in
            let preparedOutput = try repository.prepareOutput(props)
            return WorktreeAnnotationOutputMutationResult(
                preparedOutput: preparedOutput,
                sessionDetail: try repository.fetchSessionDetail(sessionID: props.sessionID)
            )
        }
    }

    func inspectOutputAttempt(attemptID: WorktreeAnnotationOutputAttemptID) async throws
        -> WorktreeAnnotationSQLiteRepository.PreparedOutput
    {
        try await restore { try $0.inspectOutputAttempt(attemptID: attemptID) }
    }

    func repeatOutputAttempt(
        sourceAttemptID: WorktreeAnnotationOutputAttemptID,
        repeatedAttemptID: WorktreeAnnotationOutputAttemptID,
        destinationPath: String?,
        now: Date
    ) async throws -> WorktreeAnnotationOutputMutationResult {
        try await mutate { repository in
            let preparedOutput = try repository.repeatOutputAttempt(
                sourceAttemptID: sourceAttemptID,
                repeatedAttemptID: repeatedAttemptID,
                destinationPath: destinationPath,
                now: now
            )
            return WorktreeAnnotationOutputMutationResult(
                preparedOutput: preparedOutput,
                sessionDetail: try repository.fetchSessionDetail(
                    sessionID: preparedOutput.attempt.sessionID
                )
            )
        }
    }

    func cancelOutputAttempt(
        attemptID: WorktreeAnnotationOutputAttemptID,
        now: Date
    ) async throws -> WorktreeAnnotationOutputMutationResult {
        try await cancelOutputAttempt(attemptID: attemptID, effectError: nil, now: now)
    }

    private func cancelOutputAttempt(
        attemptID: WorktreeAnnotationOutputAttemptID,
        effectError: String?,
        now: Date
    ) async throws -> WorktreeAnnotationOutputMutationResult {
        try await mutate { repository in
            let preparedOutput = try repository.cancelOutputAttempt(
                attemptID: attemptID,
                effectError: effectError,
                now: now
            )
            return WorktreeAnnotationOutputMutationResult(
                preparedOutput: preparedOutput,
                sessionDetail: try repository.fetchSessionDetail(
                    sessionID: preparedOutput.attempt.sessionID
                )
            )
        }
    }

    func cancelOutputAttempt(
        attemptID: WorktreeAnnotationOutputAttemptID,
        effectError: String,
        now: Date
    ) async throws -> WorktreeAnnotationOutputMutationResult {
        try await cancelOutputAttempt(
            attemptID: attemptID,
            effectError: Optional(effectError),
            now: now
        )
    }

    func finalizeOutputAttempt(
        attemptID: WorktreeAnnotationOutputAttemptID,
        eventKind: WorktreeAnnotationOutputEventKind,
        now: Date
    ) async throws -> WorktreeAnnotationOutputMutationResult {
        try await mutate { repository in
            let preparedOutput = try repository.finalizeOutputAttempt(
                attemptID: attemptID,
                eventKind: eventKind,
                now: now
            )
            return WorktreeAnnotationOutputMutationResult(
                preparedOutput: preparedOutput,
                sessionDetail: try repository.fetchSessionDetail(
                    sessionID: preparedOutput.attempt.sessionID
                )
            )
        }
    }

    func markOutputAttemptFinalizationFailed(
        attemptID: WorktreeAnnotationOutputAttemptID,
        cleanupError: String,
        now: Date
    ) async throws -> WorktreeAnnotationOutputMutationResult {
        try await mutate { repository in
            let preparedOutput = try repository.markOutputAttemptFinalizationFailed(
                attemptID: attemptID,
                cleanupError: cleanupError,
                now: now
            )
            return WorktreeAnnotationOutputMutationResult(
                preparedOutput: preparedOutput,
                sessionDetail: try repository.fetchSessionDetail(
                    sessionID: preparedOutput.attempt.sessionID
                )
            )
        }
    }

    func fetchOutputHistory(
        sessionID: WorktreeAnnotationSessionID,
        limit: Int
    ) async throws -> [WorktreeAnnotationOutputHistorySummary] {
        try await restore { try $0.fetchOutputHistory(sessionID: sessionID, limit: limit) }
    }

    func fetchOutputCandidates(
        sessionID: WorktreeAnnotationSessionID,
        expectedSessionRevision: Int,
        cursor: WorktreeAnnotationOutputCandidateCursor?,
        limit: Int
    ) async throws -> WorktreeAnnotationRepositoryOutputCandidatePage {
        try await restore {
            try $0.fetchOutputCandidates(
                sessionID: sessionID,
                expectedSessionRevision: expectedSessionRevision,
                cursor: cursor,
                limit: limit
            )
        }
    }

    func markPreparedOutputAttemptsUnknown(now: Date) async throws -> Int {
        try await mutate { try $0.markPreparedOutputAttemptsUnknown(now: now) }
    }

    func fetchUnacknowledgedRecoveryProvenance() async throws
        -> WorktreeAnnotationRecoveryProvenance?
    {
        try await restore { try $0.fetchUnacknowledgedRecoveryProvenance() }
    }

    func acknowledgeRecoveryProvenance(
        id: WorktreeAnnotationRecoveryProvenanceID,
        acknowledgedAt: Date
    ) async throws -> WorktreeAnnotationRecoveryProvenance {
        try await mutate {
            try $0.acknowledgeRecoveryProvenance(id: id, acknowledgedAt: acknowledgedAt)
        }
    }

    private func restore<TOutput: Sendable>(
        _ operation: @escaping @Sendable (WorktreeAnnotationSQLiteRepository) throws -> TOutput
    ) async throws -> TOutput {
        let result = await datastore.performLocalRestoreOperation(
            workspaceId: workspaceID,
            { repository in
                try operation(WorktreeAnnotationSQLiteRepository(databaseWriter: repository.databaseWriter))
            }
        )
        switch result {
        case .completed(let output):
            return output
        case .unavailable(let failure):
            throw failure
        }
    }

    private func mutate<TOutput: Sendable>(
        _ operation: @escaping @Sendable (WorktreeAnnotationSQLiteRepository) throws -> TOutput
    ) async throws -> TOutput {
        try await datastore.performLocalSaveOperation(workspaceId: workspaceID) { repository in
            try operation(WorktreeAnnotationSQLiteRepository(databaseWriter: repository.databaseWriter))
        }
    }
}
