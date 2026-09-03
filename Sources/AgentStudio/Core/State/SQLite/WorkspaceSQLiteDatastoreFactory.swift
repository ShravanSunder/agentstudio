import AgentStudioInfrastructure
import Foundation

package struct WorkspaceSQLiteDatastoreFactory {
    var configuration: WorkspaceSQLiteDatastoreConfiguration
    var traceRuntime: AgentStudioTraceRuntime?
    var localDatabaseReplacementObserver: WorkspaceLocalDatabaseReplacementObserver?

    package init(
        coreDatabaseURL: URL = AppDataPaths.coreSQLiteURL(),
        localDatabaseURL: URL = AppDataPaths.localSQLiteURL(),
        traceRuntime: AgentStudioTraceRuntime? = nil,
        localDatabaseReplacementObserver: WorkspaceLocalDatabaseReplacementObserver? = nil
    ) {
        self.configuration = WorkspaceSQLiteDatastoreConfiguration(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL
        )
        self.traceRuntime = traceRuntime
        self.localDatabaseReplacementObserver = localDatabaseReplacementObserver
    }

    package func makeDatastore() -> WorkspaceSQLiteDatastoreActor {
        WorkspaceSQLiteDatastoreActor(
            configuration: configuration,
            traceRuntime: traceRuntime,
            localDatabaseReplacementObserver: localDatabaseReplacementObserver
        )
    }
}
