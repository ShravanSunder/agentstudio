import Foundation
import Testing

@Suite("WorkspaceSQLiteDatastoreBoundaryTests")
struct WorkspaceSQLiteDatastoreBoundaryTests {
    @Test("WorkspaceStore SQLite path uses datastore instead of raw backend")
    func workspaceStoreSQLitePathUsesDatastore() throws {
        let source = try projectSource(
            "Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift"
        )

        #expect(source.contains("sqliteDatastore: WorkspaceSQLiteDatastore?"))
        #expect(source.contains("private let sqliteDatastore: WorkspaceSQLiteDatastore?"))
        #expect(!source.contains("private let sqliteBackend: WorkspaceSQLiteStoreBackend?"))
        #expect(!source.contains("sqliteBackend: WorkspaceSQLiteStoreBackend?"))
    }

    @Test("legacy SQLite importer reaches persistence through datastore APIs")
    func legacySQLiteImporterUsesDatastoreBoundary() throws {
        let source = try projectSource(
            "Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore+LegacySQLiteImport.swift"
        )

        #expect(source.contains("sqliteDatastore: WorkspaceSQLiteDatastore"))
        #expect(source.contains("await sqliteDatastore.legacyImportStatus("))
        #expect(source.contains("await sqliteDatastore.completedSnapshotStatus("))
        #expect(!source.contains("sqliteBackend: WorkspaceSQLiteStoreBackend"))
        #expect(!source.contains("WorkspaceCoreRepository"))
        #expect(!source.contains("fetchLegacyWorkspaceImportStatus("))
    }

    @Test("AppDelegate boot owns datastore, not raw SQLite backends")
    func appDelegateBootOwnsDatastoreBoundary() throws {
        let appDelegateSource = try projectSource("Sources/AgentStudio/App/Boot/AppDelegate.swift")
        let workspaceBootSource = try projectSource("Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift")
        let inboxBootSource = try projectSource(
            "Sources/AgentStudio/App/Boot/AppDelegate+InboxNotificationBoot.swift"
        )

        #expect(appDelegateSource.contains("var workspaceSQLiteDatastore: WorkspaceSQLiteDatastore?"))
        #expect(!appDelegateSource.contains("var workspaceSQLiteStoreBackend: WorkspaceSQLiteStoreBackend?"))
        #expect(!appDelegateSource.contains("var workspaceLocalSQLiteStoreBackend: WorkspaceLocalSQLiteStoreBackend?"))

        #expect(workspaceBootSource.contains("makeWorkspaceSQLiteDatastore(traceRuntime: traceRuntime)"))
        #expect(workspaceBootSource.contains("sqliteDatastore: workspaceSQLiteDatastore"))
        #expect(!workspaceBootSource.contains("workspaceSQLiteStoreBackend"))
        #expect(!workspaceBootSource.contains("workspaceLocalSQLiteStoreBackend"))
        #expect(!workspaceBootSource.contains("WorkspaceSQLiteStoreBackendFactory("))

        #expect(!inboxBootSource.contains("makeInboxNotificationSQLiteRepository("))
        #expect(!inboxBootSource.contains("workspaceLocalSQLiteStoreBackend"))
        #expect(!inboxBootSource.contains("InboxNotificationSQLiteRepository("))
    }

    @Test("configuration backed datastore keeps local SQLite IO behind actor caches")
    func configurationBackedDatastoreKeepsLocalSQLiteIOBehindActorCaches() throws {
        let source = try projectSource("Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastore.swift")

        #expect(
            source.contains(
                "makeLocalRepository: { _ in throw WorkspaceSQLiteDatastoreError.useDatastoreLocalRepositoryCache }"
            )
        )
        #expect(
            source.contains(
                "makeLocalRestoreRepository: { _ in throw WorkspaceSQLiteDatastoreError.useDatastoreLocalRepositoryCache }"
            )
        )
        #expect(!source.contains("func hasCompletedSnapshot(workspaceId: UUID) async"))
    }

    private func projectSource(_ relativePath: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        return try String(contentsOf: projectRoot.appending(path: relativePath), encoding: .utf8)
    }
}
