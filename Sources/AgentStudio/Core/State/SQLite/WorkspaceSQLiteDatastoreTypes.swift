import Foundation

struct WorkspaceSQLiteDatastoreConfiguration: Sendable {
    var coreDatabaseURL: URL
    var localDatabaseURL: @Sendable (UUID) -> URL
}

enum WorkspaceSQLiteDatastoreError: Error, Equatable, Sendable {
    case missingConfiguration
    case useDatastoreLocalRepositoryCache
    case coreQuarantineFailed
}

struct WorkspaceSQLiteDatastoreFailure: Error, Equatable, Sendable {
    let description: String

    init(_ error: any Error) {
        self.description = String(describing: error)
    }
}

enum LegacyImportFailureRecordOutcome: Equatable, Sendable {
    case recorded
    case failedToRecord(WorkspaceSQLiteDatastoreFailure)
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
        case loaded(WorkspaceSQLiteSnapshot, recoveryEvents: [PersistenceRecoveryEvent])
        case uninitialized(recoveryEvents: [PersistenceRecoveryEvent])
        case unavailable(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
    }

    enum RepositoryTopologyLoadResult: Equatable, Sendable {
        case loaded(RepositoryTopologySQLiteSnapshot)
        case uninitialized
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    enum LegacyImportStatusResult: Equatable, Sendable {
        case found(WorkspaceCoreRepository.LegacyImportStatusRecord)
        case missing
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    enum LocalLegacyImportDecisionResult: Equatable, Sendable {
        case found(WorkspaceLocalSQLiteLegacyImportDecision)
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    enum CompletedSnapshotStatusResult: Equatable, Sendable {
        case completed(Bool, recoveryEvents: [PersistenceRecoveryEvent])
        case unavailable(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
    }

    enum WorkspaceRowsInspectionResult: Equatable, Sendable {
        case hasWorkspaceRows
        case empty
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    enum ActiveWorkspaceSelectionInspectionResult: Equatable, Sendable {
        case present
        case missing
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    enum LocalCacheLoadResult: Equatable, Sendable {
        case loaded(LocalCacheLoadPayload)
        case unavailable(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
    }

    struct LocalCacheLoadPayload: Equatable, Sendable {
        var cacheState: WorkspaceLocalRepository.CacheStateRecord?
        var recentTargets: [RecentWorkspaceTarget]?
        var cacheLegacyDecision: WorkspaceLocalSQLiteLegacyImportDecision
        var recentTargetLegacyDecision: WorkspaceLocalSQLiteLegacyImportDecision
        var recoveryEvents: [PersistenceRecoveryEvent]
    }

    enum LocalUILoadResult: Equatable, Sendable {
        case loaded(LocalUILoadPayload)
        case unavailable(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
    }

    struct LocalUILoadPayload: Equatable, Sendable {
        var state: WorkspaceLocalRepository.SidebarStateRecord?
        var legacyDecision: WorkspaceLocalSQLiteLegacyImportDecision
        var recoveryEvents: [PersistenceRecoveryEvent]
    }

    enum LocalSidebarLoadResult: Equatable, Sendable {
        case loaded(LocalSidebarLoadPayload)
        case unavailable(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
    }

    struct LocalSidebarLoadPayload: Equatable, Sendable {
        var expandedGroups: Set<SidebarGroupKey>?
        var legacyDecision: WorkspaceLocalSQLiteLegacyImportDecision
        var recoveryEvents: [PersistenceRecoveryEvent]
    }

    enum LocalRepositoryOperationResult<Output: Sendable>: Sendable {
        case completed(Output, recoveryEvents: [PersistenceRecoveryEvent])
        case unavailable(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
    }
}
