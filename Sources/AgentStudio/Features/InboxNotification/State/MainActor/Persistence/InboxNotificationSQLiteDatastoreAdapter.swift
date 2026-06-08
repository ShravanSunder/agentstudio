import Foundation

struct InboxNotificationSQLiteDatastoreAdapter {
    enum LoadResult: Sendable {
        case loaded(InboxNotificationStore.SQLiteLoadSnapshot, recoveryEvents: [PersistenceRecoveryEvent])
        case unavailable(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
    }

    struct BootDecision: Sendable {
        var allowLegacyFilePersistence: Bool
        var allowLegacyFileImport: Bool
        var canArchiveLegacyInboxFileAfterBlockedImport: Bool
        var recoveryEvents: [PersistenceRecoveryEvent]
    }

    let workspaceId: UUID
    let datastore: WorkspaceSQLiteDatastore

    func bootDecision() async -> BootDecision {
        let legacyImportDecision: WorkspaceLocalSQLiteLegacyImportDecision
        switch await datastore.localLegacyImportDecision(workspaceId: workspaceId, lane: .local) {
        case .found(let decision):
            legacyImportDecision = decision
        case .unavailable:
            legacyImportDecision = .blockReplayBlockArchive
        }
        switch await datastore.performLocalRestoreOperation(workspaceId: workspaceId, Self.makeBootDecision) {
        case .completed(let decision, let recoveryEvents):
            return .init(
                allowLegacyFilePersistence: true,
                allowLegacyFileImport: legacyImportDecision.allowsLegacyImport,
                canArchiveLegacyInboxFileAfterBlockedImport: legacyImportDecision.canArchiveLegacyFile
                    && decision.hasMaterializedLegacyInboxImport,
                recoveryEvents: recoveryEvents
            )
        case .unavailable(_, let recoveryEvents):
            return .init(
                allowLegacyFilePersistence: false,
                allowLegacyFileImport: false,
                canArchiveLegacyInboxFileAfterBlockedImport: false,
                recoveryEvents: recoveryEvents
            )
        }
    }

    func load() async -> LoadResult {
        switch await datastore.performLocalRestoreOperation(workspaceId: workspaceId, Self.loadSnapshot) {
        case .completed(let snapshot, let recoveryEvents):
            return .loaded(snapshot, recoveryEvents: recoveryEvents)
        case .unavailable(let failure, let recoveryEvents):
            return .unavailable(failure, recoveryEvents: recoveryEvents)
        }
    }

    func save(_ snapshot: InboxNotificationStore.SQLiteSnapshot) async throws {
        try await datastore.performLocalSaveOperation(workspaceId: workspaceId) { repository in
            let inboxRepository = InboxNotificationSQLiteRepository(
                workspaceId: workspaceId,
                databaseWriter: repository.databaseWriter
            )
            if snapshot.markLegacyImport {
                try inboxRepository.replaceLegacyImportSnapshot(
                    notifications: snapshot.notifications,
                    collapsedGroups: snapshot.collapsedGroups
                )
            } else {
                try inboxRepository.replaceSnapshot(
                    notifications: snapshot.notifications,
                    collapsedGroups: snapshot.collapsedGroups
                )
            }
        }
    }

    private struct BootDecisionPayload: Sendable {
        var hasMaterializedLegacyInboxImport: Bool
    }

    private static func makeBootDecision(repository: WorkspaceLocalRepository) throws -> BootDecisionPayload {
        let inboxRepository = InboxNotificationSQLiteRepository(
            workspaceId: repository.workspaceId,
            databaseWriter: repository.databaseWriter
        )
        return .init(
            hasMaterializedLegacyInboxImport: try inboxRepository.hasMaterializedLegacyImport()
        )
    }

    private static func loadSnapshot(repository: WorkspaceLocalRepository) throws
        -> InboxNotificationStore
        .SQLiteLoadSnapshot
    {
        let inboxRepository = InboxNotificationSQLiteRepository(
            workspaceId: repository.workspaceId,
            databaseWriter: repository.databaseWriter
        )
        let hasPersistedState = try inboxRepository.hasPersistedState()
        return .init(
            notifications: hasPersistedState ? try inboxRepository.fetchNotifications() : [],
            collapsedGroups: hasPersistedState ? try inboxRepository.fetchCollapsedGroups() : [],
            hasPersistedState: hasPersistedState,
            hasMaterializedLegacyImport: try inboxRepository.hasMaterializedLegacyImport()
        )
    }
}
