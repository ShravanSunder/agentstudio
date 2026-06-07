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

    static func archiveLegacyWorkspaceFilesIfReady(
        workspaceId: UUID,
        persistor: WorkspacePersistor,
        sqliteDatastore: WorkspaceSQLiteDatastore?,
        canArchiveLegacyCompanionFiles: Bool,
        now: @Sendable () -> Date = Date.init
    ) async -> Outcome {
        let hasSQLiteBackend = sqliteDatastore != nil
        guard let sqliteDatastore else {
            return .skipped(.missingSQLiteDatastore)
        }

        let hasCompletedSnapshot: Bool
        do {
            hasCompletedSnapshot = try await sqliteDatastore.hasCompletedSnapshot(workspaceId: workspaceId)
        } catch {
            return .skipped(.snapshotStatusUnavailable(.init(error)))
        }

        let hasLegacyWorkspaceFiles = persistor.hasLegacyWorkspaceFiles(for: workspaceId)
        let shouldArchiveLegacyFiles = WorkspaceLegacyArchiveReadiness.canArchiveLegacyFiles(
            hasSQLiteBackend: hasSQLiteBackend,
            hasCompletedSnapshot: hasCompletedSnapshot,
            hasLegacyWorkspaceFiles: hasLegacyWorkspaceFiles,
            canArchiveLegacyCompanionFiles: canArchiveLegacyCompanionFiles
        )
        guard canArchiveLegacyCompanionFiles else {
            return .skipped(.incompleteCompanionImports)
        }
        guard shouldArchiveLegacyFiles else {
            return .skipped(.notReady)
        }

        do {
            try await sqliteDatastore.markLegacyWorkspaceCompanionImportsCompleted(
                workspaceId: workspaceId,
                importedAt: now()
            )
        } catch {
            return .skipped(.companionStatusUpdateFailed(.init(error)))
        }

        guard let result = persistor.archiveLegacyWorkspaceFiles(for: workspaceId) else {
            return .skipped(.noLegacyFiles)
        }
        guard result.succeeded else {
            return .archiveIncomplete(result)
        }

        do {
            try await sqliteDatastore.markLegacyWorkspaceArchived(
                workspaceId: workspaceId,
                archivedAt: now()
            )
        } catch {
            return .archivedButStatusUpdateFailed(
                directoryName: result.archiveDirectoryName,
                .init(error)
            )
        }
        return .archived(directoryName: result.archiveDirectoryName)
    }
}
