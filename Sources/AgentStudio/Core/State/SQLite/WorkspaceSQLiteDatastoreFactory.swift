import Foundation

struct WorkspaceSQLiteDatastoreFactory {
    var configuration: WorkspaceSQLiteDatastoreConfiguration

    init(
        coreDatabaseURL: URL = AppDataPaths.coreSQLiteURL(),
        localDatabaseURL: @escaping @Sendable (UUID) -> URL = { workspaceId in
            AppDataPaths.workspaceLocalSQLiteURL(workspaceId: workspaceId)
        }
    ) {
        self.configuration = WorkspaceSQLiteDatastoreConfiguration(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL
        )
    }

    func makeDatastore() -> WorkspaceSQLiteDatastore {
        WorkspaceSQLiteDatastore(configuration: configuration)
    }
}
