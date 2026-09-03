import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Foundation

package struct InboxNotificationSQLiteDatastoreAdapter {
    enum LoadResult: Sendable {
        case loaded(InboxNotificationStore.SQLiteSnapshot)
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    package let workspaceId: UUID
    package let datastore: WorkspaceSQLiteDatastoreActor

    package init(workspaceId: UUID, datastore: WorkspaceSQLiteDatastoreActor) {
        self.workspaceId = workspaceId
        self.datastore = datastore
    }

    func load() async -> LoadResult {
        switch await datastore.performLocalRestoreOperation(workspaceId: workspaceId, Self.loadSnapshot) {
        case .completed(let snapshot):
            return .loaded(snapshot)
        case .unavailable(let failure):
            return .unavailable(failure)
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
