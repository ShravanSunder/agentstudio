import AgentStudioTestSupport
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("WorkspaceSQLiteDatastoreBoundaryTests")
struct WorkspaceSQLiteDatastoreBoundaryTests {
    @Test("WorkspaceStore SQLite path uses datastore instead of raw backend")
    func workspaceStoreSQLitePathUsesDatastore() throws {
        let source = try projectSource(
            "Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift"
        )

        #expect(source.contains("sqliteDatastore: WorkspaceSQLiteDatastoreActor?"))
        #expect(source.contains("private let sqliteDatastore: WorkspaceSQLiteDatastoreActor?"))
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
            "Sources/AgentStudio/App/Coordination/WorkspaceSettingsStore.swift"
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

        #expect(appDelegateSource.contains("var workspaceSQLiteDatastore: WorkspaceSQLiteDatastoreActor?"))
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

    @Test("configuration-backed datastore refuses loads until it prepares its databases")
    func configurationBackedDatastoreStartsUnprepared() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-datastore-preparation-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let datastore = WorkspaceSQLiteDatastoreActor(
            configuration: .init(
                coreDatabaseURL: rootDirectory.appending(path: "core.sqlite"),
                localDatabaseURL: rootDirectory.appending(path: "local.sqlite")
            )
        )

        guard case .unavailable = await datastore.loadAuthoritativeCoreSnapshot() else {
            Issue.record("Expected an unprepared datastore to refuse the core snapshot load")
            return
        }
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("Expected the configuration-backed datastore to prepare its databases")
            return
        }
        #expect(await datastore.loadAuthoritativeCoreSnapshot() == .uninitialized)
    }

    @Test("datastore built from injected prepared capabilities starts prepared")
    @MainActor
    func injectedCapabilitiesStartPrepared() async throws {
        let coreDatabaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        let localDatabaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceCoreMigrations.migrate(coreDatabaseQueue)
        try WorkspaceLocalMigrations.migrate(localDatabaseQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreDatabaseQueue)
        let preparedApplicationLocalRepository = WorkspaceLocalRepository(
            workspaceId: UUIDv7.generate(),
            databaseWriter: localDatabaseQueue
        )
        let datastore = try await preparedWorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            preparedApplicationLocalRepository: preparedApplicationLocalRepository
        )

        #expect(await datastore.loadAuthoritativeCoreSnapshot() == .uninitialized)

        let preparation = await datastore.prepareDatabasesForBoot()
        guard case .prepared = preparation else {
            Issue.record("Expected prepared datastore, got \(preparation)")
            return
        }
    }

    private func projectSource(_ relativePath: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        return try String(contentsOf: projectRoot.appending(path: relativePath), encoding: .utf8)
    }
}
