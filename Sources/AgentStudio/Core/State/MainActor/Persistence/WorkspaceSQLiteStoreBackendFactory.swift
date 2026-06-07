import Foundation
import os.log

private let workspaceSQLiteBackendFactoryLogger = Logger(
    subsystem: "com.agentstudio",
    category: "WorkspaceSQLiteStoreBackendFactory"
)

@MainActor
struct WorkspaceSQLiteStoreBackendFactory {
    var coreDatabaseURL: URL
    var localDatabaseURL: @MainActor (UUID) -> URL
    var recoveryReporter: PersistenceRecoveryReporter?

    init(
        coreDatabaseURL: URL = AppDataPaths.coreSQLiteURL(),
        localDatabaseURL: @escaping @MainActor (UUID) -> URL = { workspaceId in
            AppDataPaths.workspaceLocalSQLiteURL(workspaceId: workspaceId)
        },
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.coreDatabaseURL = coreDatabaseURL
        self.localDatabaseURL = localDatabaseURL
        self.recoveryReporter = recoveryReporter
    }

    func makeBackend() -> WorkspaceSQLiteStoreBackend? {
        do {
            return try openBackend()
        } catch {
            workspaceSQLiteBackendFactoryLogger.error(
                "Failed to prepare SQLite workspace backend before quarantine: \(error.localizedDescription)"
            )
        }

        let quarantine = SQLiteSidecarQuarantine.quarantine(databaseURL: coreDatabaseURL)
        recoveryReporter?(
            .init(
                store: .workspace,
                workspaceId: nil,
                recovery: quarantine.succeeded ? .quarantinedAndReset : .quarantineFailed,
                quarantinedFilename: quarantine.recoveryFilename
            )
        )

        do {
            return try openBackend()
        } catch {
            workspaceSQLiteBackendFactoryLogger.error(
                "Failed to prepare SQLite workspace backend after quarantine: \(error.localizedDescription)"
            )
            recoveryReporter?(
                .init(
                    store: .workspace,
                    workspaceId: nil,
                    recovery: .resetToDefaults
                )
            )
            return nil
        }
    }

    private func openBackend() throws -> WorkspaceSQLiteStoreBackend {
        let coreDatabasePool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: coreDatabaseURL,
            label: "AgentStudio.sqlite.core"
        )
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreDatabasePool)
        try coreRepository.migrate()
        return WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { workspaceId in
                let localDatabasePool = try SQLiteDatabaseFactory.makeFileBackedPool(
                    at: localDatabaseURL(workspaceId),
                    label: "AgentStudio.sqlite.local.\(workspaceId.uuidString)"
                )
                let localRepository = WorkspaceLocalRepository(
                    workspaceId: workspaceId,
                    databaseWriter: localDatabasePool
                )
                try localRepository.migrate()
                return localRepository
            }
        )
    }
}
