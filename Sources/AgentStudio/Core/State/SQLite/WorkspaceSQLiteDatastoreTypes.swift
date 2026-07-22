import Foundation

struct WorkspaceSQLiteDatastoreConfiguration: Sendable {
    var coreDatabaseURL: URL
    var localDatabaseURL: URL
}

enum WorkspaceSQLiteDatastoreError: Error, Equatable, Sendable {
    case missingConfiguration
    case useDatastoreApplicationLocalRepositoryBundle
}

struct WorkspaceSQLiteDatastoreFailure: Error, Equatable, Sendable {
    let description: String

    init(_ error: any Error) {
        self.description = String(describing: error)
    }
}

extension WorkspaceSQLiteDatastore {
    enum LocalRepositoryOpenMode: Equatable, Sendable {
        case restore
        case save
    }

    enum ProbeEvent: Equatable, Sendable {
        case saveWorkspaceSnapshot
        case saveWorkspaceSnapshotSucceeded
        case saveWorkspaceSnapshotFailed
        case loadWorkspaceSnapshot
        case localRepositoryOpened(UUID, LocalRepositoryOpenMode)
    }

    enum LoadResult: Equatable, Sendable {
        case loaded(WorkspaceSQLiteSnapshot)
        case uninitialized
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    enum CoreLoadResult: Equatable, Sendable {
        case loaded(WorkspaceCoreLoadSnapshot)
        case uninitialized
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    enum RepositoryTopologyLoadResult: Equatable, Sendable {
        case loaded(RepositoryTopologySQLiteSnapshot)
        case uninitialized
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    enum LocalCacheLoadResult: Equatable, Sendable {
        case loaded(LocalCacheLoadPayload)
        case unavailable(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
    }

    struct LocalCacheLoadPayload: Equatable, Sendable {
        var cacheState: WorkspaceLocalRepository.CacheStateRecord
        var recentTargets: [RecentWorkspaceTarget]
        var recoveryEvents: [PersistenceRecoveryEvent]
    }

    enum LocalUILoadResult: Equatable, Sendable {
        case loaded(LocalUILoadPayload)
        case unavailable(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
    }

    struct LocalUILoadPayload: Equatable, Sendable {
        var state: WorkspaceLocalRepository.SidebarStateRecord?
        var recoveryEvents: [PersistenceRecoveryEvent]
    }

    enum LocalSidebarLoadResult: Equatable, Sendable {
        case loaded(LocalSidebarLoadPayload)
        case unavailable(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
    }

    struct LocalSidebarLoadPayload: Equatable, Sendable {
        var expandedGroups: Set<SidebarGroupKey>
        var recoveryEvents: [PersistenceRecoveryEvent]
    }

    enum LocalSettingsLoadResult: Equatable, Sendable {
        case loaded(LocalSettingsLoadPayload)
        case unavailable(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
    }

    struct LocalSettingsLoadPayload: Equatable, Sendable {
        var editor: WorkspaceLocalRepository.EditorPreferencesRecord
        var repoExplorer: WorkspaceLocalRepository.RepoExplorerPreferencesRecord
        var inboxNotification: WorkspaceLocalRepository.InboxNotificationPreferencesRecord
        var recoveryEvents: [PersistenceRecoveryEvent]
    }

    enum LocalRepositoryOperationResult<Output: Sendable>: Sendable {
        case completed(Output, recoveryEvents: [PersistenceRecoveryEvent])
        case unavailable(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
    }
}
