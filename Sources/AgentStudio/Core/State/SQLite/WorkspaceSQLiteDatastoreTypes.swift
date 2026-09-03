import Foundation

struct WorkspaceSQLiteDatastoreConfiguration: Sendable {
    var coreDatabaseURL: URL
    var localDatabaseURL: URL
}

enum WorkspaceSQLiteDatastoreError: Error, Equatable, Sendable {
    case missingConfiguration
    case databasesNotPrepared
    case applicationLocalRepositoryUnavailable
    case useDatastoreApplicationLocalRepositoryBundle
}

package struct WorkspaceSQLiteDatastoreFailure: Error, Equatable, Sendable {
    package enum Kind: Equatable, Sendable {
        case stateBridge
        case database
    }

    package let kind: Kind
    package let description: String

    init(_ error: any Error) {
        self.kind = error is WorkspaceSQLiteStateBridgeError ? .stateBridge : .database
        self.description = String(describing: error)
    }
}

extension WorkspaceSQLiteDatastore {
    enum LocalDatabaseRecoveryReason: Equatable, Sendable {
        case corruptDatabase
        case incompleteFileSet
    }

    struct LocalDatabaseRecovery: Equatable, Sendable {
        var reason: LocalDatabaseRecoveryReason
    }

    enum PreparedCoreDatabase: Equatable, Sendable {
        case ready(WorkspaceCoreRepository.AuthoritativeSnapshot)
        case uninitialized
    }

    enum PreparedLocalDatabase: Equatable, Sendable {
        case available(recovery: LocalDatabaseRecovery?)
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    package struct DatabasePreparationReceipt: Equatable, Sendable {
        var core: PreparedCoreDatabase
        var local: PreparedLocalDatabase
    }

    package enum CoreDatabasePreparationFailureKind: Equatable, Sendable {
        case sqliteUnavailable
        case compositionRejected
        case topologyRejected
    }

    package struct CoreDatabasePreparationFailure: Error, Equatable, Sendable {
        package var kind: CoreDatabasePreparationFailureKind
        var failure: WorkspaceSQLiteDatastoreFailure
    }

    package enum DatabasePreparationResult: Equatable, Sendable {
        case prepared(DatabasePreparationReceipt)
        case failed(CoreDatabasePreparationFailure)
    }

    package enum ProbeEvent: Equatable, Sendable {
        case saveWorkspaceSnapshot
        case saveWorkspaceSnapshotSucceeded
        case saveWorkspaceSnapshotFailed
        case loadWorkspaceSnapshot
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
        case loaded(WorkspaceLocalRepository.CacheStateRecord)
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    enum ApplicationEntityRecencyLoadResult: Equatable, Sendable {
        case loaded([ApplicationEntityRecency])
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    enum RepositoryLocalActivityLoadResult: Equatable, Sendable {
        case loaded(RepositoryLocalActivitySnapshot)
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    enum WorkspaceEntityRecencyLoadResult: Equatable, Sendable {
        case loaded([WorkspaceEntityRecency])
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    enum LocalUILoadResult: Equatable, Sendable {
        case loaded(WorkspaceLocalRepository.SidebarStateRecord?)
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    enum LocalSidebarLoadResult: Equatable, Sendable {
        case loaded(Set<SidebarGroupKey>)
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    package enum LocalSettingsValue<Value: Equatable & Sendable>: Equatable, Sendable {
        case loaded(Value)
        case defaulted(WorkspaceSQLiteDatastoreFailure)
    }

    package enum LocalSettingsLoadResult: Equatable, Sendable {
        case loaded(LocalSettingsLoadPayload)
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    package struct LocalSettingsLoadPayload: Equatable, Sendable {
        package private(set) var editor:
            LocalSettingsValue<
                WorkspaceLocalRepository.EditorPreferencesRecord
            >
        package private(set) var repoExplorer:
            LocalSettingsValue<
                WorkspaceLocalRepository.RepoExplorerPreferencesRecord
            >
    }

    package enum LocalRepositoryOperationResult<Output: Sendable>: Sendable {
        case completed(Output)
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }
}
