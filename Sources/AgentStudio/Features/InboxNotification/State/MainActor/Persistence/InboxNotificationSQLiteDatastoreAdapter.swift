import Foundation

struct InboxNotificationSQLiteDatastoreAdapter {
    enum LoadResult: Sendable {
        case loaded(InboxNotificationStore.SQLiteSnapshot, recoveryEvents: [PersistenceRecoveryEvent])
        case unavailable(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
    }

    let workspaceId: UUID
    let datastore: WorkspaceSQLiteDatastore

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
            try inboxRepository.replaceSnapshot(
                notifications: snapshot.notifications,
                collapsedGroups: snapshot.collapsedGroups
            )
        }
    }

    private static func loadSnapshot(repository: WorkspaceLocalRepository) throws
        -> InboxNotificationStore.SQLiteSnapshot
    {
        let inboxRepository = InboxNotificationSQLiteRepository(
            workspaceId: repository.workspaceId,
            databaseWriter: repository.databaseWriter
        )
        return .init(
            notifications: try inboxRepository.fetchNotifications(),
            collapsedGroups: try inboxRepository.fetchCollapsedGroups()
        )
    }
}
