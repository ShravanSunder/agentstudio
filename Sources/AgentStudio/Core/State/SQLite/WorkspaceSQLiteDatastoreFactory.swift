import AgentStudioInfrastructure
import Foundation

package struct WorkspaceSQLiteDatastoreFactory {
    var configuration: WorkspaceSQLiteDatastoreConfiguration
    var traceRuntime: AgentStudioTraceRuntime?

    package init(
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

    package func makeDatastore() -> WorkspaceSQLiteDatastore {
        WorkspaceSQLiteDatastore(configuration: configuration, traceRuntime: traceRuntime)
    }
}
