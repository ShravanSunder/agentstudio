import Foundation

struct WorkspaceSQLiteDatastoreFactory {
    var configuration: WorkspaceSQLiteDatastoreConfiguration
    var traceRuntime: AgentStudioTraceRuntime?

    init(
        coreDatabaseURL: URL = AppDataPaths.coreSQLiteURL(),
        localDatabaseURL: URL = AppDataPaths.localSQLiteURL(),
        traceRuntime: AgentStudioTraceRuntime? = nil
    ) {
        self.configuration = WorkspaceSQLiteDatastoreConfiguration(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL
        )
        self.traceRuntime = traceRuntime
    }

    func makeDatastore() -> WorkspaceSQLiteDatastore {
        WorkspaceSQLiteDatastore(configuration: configuration, traceRuntime: traceRuntime)
    }
}
