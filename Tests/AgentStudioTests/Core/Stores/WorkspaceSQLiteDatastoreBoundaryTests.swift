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

    @Test("workspace composition startup has no legacy JSON import archive or fallback path")
    func workspaceCompositionStartupHasNoLegacyJSONPath() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let workspaceStoreSource = try projectSource(
            "Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift"
        )
        let restoreAsyncStart = try #require(
            workspaceStoreSource.range(of: "func loadCanonicalComposition() async -> WorkspaceStoreLoadResult")
        )
        let restoreAsyncEnd = try #require(
            workspaceStoreSource.range(
                of: "private func initializeAndApplyDefaultWorkspace",
                range: restoreAsyncStart.upperBound..<workspaceStoreSource.endIndex
            )
        )
        let restoreAsyncSource = workspaceStoreSource[restoreAsyncStart.lowerBound..<restoreAsyncEnd.lowerBound]
        let appDelegateSource = try projectSource("Sources/AgentStudio/App/Boot/AppDelegate.swift")
        let workspaceBootSource = try projectSource("Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift")
        let settingsSource = try projectSource(
            "Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSettingsStore.swift"
        )

        #expect(!restoreAsyncSource.contains("restoreFromLegacyJSON"))
        #expect(!restoreAsyncSource.contains("persistLegacyJSONSnapshot"))
        #expect(!restoreAsyncSource.contains("saveImportedLegacySnapshot"))
        #expect(!restoreAsyncSource.contains("legacyImportStatus"))
        #expect(!workspaceStoreSource.contains("WorkspacePersistor"))
        #expect(!workspaceStoreSource.contains("func restore()"))
        #expect(!workspaceStoreSource.contains("func flush()"))
        #expect(!appDelegateSource.contains("WorkspaceLegacyArchiveCoordinator"))
        #expect(!workspaceBootSource.contains("WorkspaceLegacyArchiveCoordinator"))
        #expect(
            !FileManager.default.fileExists(
                atPath: projectRoot.appending(
                    path: "Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistor.swift"
                ).path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: projectRoot.appending(
                    path: "Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistor+Payloads.swift"
                ).path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: projectRoot.appending(
                    path: "Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore+LegacySQLiteImport.swift"
                ).path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: projectRoot.appending(
                    path:
                        "Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistor+LegacyDrawerCursorRouting.swift"
                ).path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: projectRoot.appending(
                    path: "Sources/AgentStudio/App/Boot/WorkspaceLegacyArchiveCoordinator.swift"
                ).path
            )
        )

        #expect(!settingsSource.contains("JSONDecoder()"))
        #expect(!settingsSource.contains("JSONEncoder()"))
        #expect(
            workspaceBootSource.contains(
                "await workspaceSettingsStore.restoreAsync(for: store.identityAtom.workspaceId)"
            )
        )
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
        #expect(workspaceBootSource.contains("sqliteDatastore: sqliteDatastore"))
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
