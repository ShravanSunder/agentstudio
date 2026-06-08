import Foundation

enum WorkspaceLegacyArchiveCoordinator {
    enum SkipReason: Equatable, Sendable {
        case missingSQLiteDatastore
        case snapshotStatusUnavailable(WorkspaceSQLiteDatastoreFailure)
        case incompleteCompanionImports
        case notReady
        case companionStatusUpdateFailed(WorkspaceSQLiteDatastoreFailure)
        case noLegacyFiles
    }

    enum Outcome: Equatable, Sendable {
        case skipped(SkipReason)
        case archived(directoryName: String)
        case archiveIncomplete(WorkspacePersistor.LegacyArchiveResult)
        case archivedButStatusUpdateFailed(directoryName: String, WorkspaceSQLiteDatastoreFailure)
    }

    struct ArchiveResult: Equatable, Sendable {
        var outcome: Outcome
        var recoveryEvents: [PersistenceRecoveryEvent]
    }

    static func archiveLegacyWorkspaceFilesIfReady(
        workspaceId: UUID,
        persistor: WorkspacePersistor,
        sqliteDatastore: WorkspaceSQLiteDatastore?,
        canArchiveLegacyCompanionFiles: Bool,
        now: @Sendable () -> Date = Date.init
    ) async -> ArchiveResult {
        let hasSQLiteBackend = sqliteDatastore != nil
        guard let sqliteDatastore else {
            return .init(outcome: .skipped(.missingSQLiteDatastore), recoveryEvents: [])
        }

        let hasCompletedSnapshot: Bool
        var recoveryEvents: [PersistenceRecoveryEvent] = []
        switch await sqliteDatastore.completedSnapshotStatus(workspaceId: workspaceId) {
        case .completed(let isCompleted, let events):
            hasCompletedSnapshot = isCompleted
            recoveryEvents.append(contentsOf: events)
        case .unavailable(let failure, let events):
            return .init(
                outcome: .skipped(.snapshotStatusUnavailable(failure)),
                recoveryEvents: events
            )
        }

        let hasLegacyWorkspaceFiles = persistor.hasLegacyWorkspaceFiles(for: workspaceId)
        let shouldArchiveLegacyFiles = WorkspaceLegacyArchiveReadiness.canArchiveLegacyFiles(
            hasSQLiteBackend: hasSQLiteBackend,
            hasCompletedSnapshot: hasCompletedSnapshot,
            hasLegacyWorkspaceFiles: hasLegacyWorkspaceFiles,
            canArchiveLegacyCompanionFiles: canArchiveLegacyCompanionFiles
        )
        guard canArchiveLegacyCompanionFiles else {
            return .init(outcome: .skipped(.incompleteCompanionImports), recoveryEvents: recoveryEvents)
        }
        guard shouldArchiveLegacyFiles else {
            return .init(outcome: .skipped(.notReady), recoveryEvents: recoveryEvents)
        }

        do {
            try await sqliteDatastore.markLegacyWorkspaceCompanionImportsCompleted(
                workspaceId: workspaceId,
                importedAt: now()
            )
        } catch {
            return .init(
                outcome: .skipped(.companionStatusUpdateFailed(.init(error))),
                recoveryEvents: recoveryEvents
            )
        }

        guard let result = persistor.archiveLegacyWorkspaceFiles(for: workspaceId) else {
            return .init(outcome: .skipped(.noLegacyFiles), recoveryEvents: recoveryEvents)
        }
        guard result.succeeded else {
            return .init(outcome: .archiveIncomplete(result), recoveryEvents: recoveryEvents)
        }

        do {
            try await sqliteDatastore.markLegacyWorkspaceArchived(
                workspaceId: workspaceId,
                archivedAt: now()
            )
        } catch {
            return .init(
                outcome: .archivedButStatusUpdateFailed(
                    directoryName: result.archiveDirectoryName,
                    .init(error)
                ),
                recoveryEvents: recoveryEvents
            )
        }
        return .init(
            outcome: .archived(directoryName: result.archiveDirectoryName),
            recoveryEvents: recoveryEvents
        )
    }
}
