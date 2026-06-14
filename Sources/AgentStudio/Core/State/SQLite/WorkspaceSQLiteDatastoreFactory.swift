import Foundation

struct WorkspaceSQLiteDatastoreFactory {
    var configuration: WorkspaceSQLiteDatastoreConfiguration
    var traceRuntime: AgentStudioTraceRuntime?
    var beforeCoreSnapshotCommit: @Sendable (WorkspaceSQLiteSnapshot) throws -> Void

    init(
        coreDatabaseURL: URL = AppDataPaths.coreSQLiteURL(),
        localDatabaseURL: @escaping @Sendable (UUID) -> URL = { workspaceId in
            AppDataPaths.workspaceLocalSQLiteURL(workspaceId: workspaceId)
        },
        traceRuntime: AgentStudioTraceRuntime? = nil,
        beforeCoreSnapshotCommit: @escaping @Sendable (WorkspaceSQLiteSnapshot) throws -> Void = { _ in }
    ) {
        self.configuration = WorkspaceSQLiteDatastoreConfiguration(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL
        )
        self.traceRuntime = traceRuntime
        self.beforeCoreSnapshotCommit = beforeCoreSnapshotCommit
    }

    func makeDatastore() -> WorkspaceSQLiteDatastore {
        WorkspaceSQLiteDatastore(
            configuration: configuration,
            traceRuntime: traceRuntime,
            beforeCoreSnapshotCommit: beforeCoreSnapshotCommit
        )
    }
}
