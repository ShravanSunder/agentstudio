import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteStoreBackendFactoryTests", .serialized)
struct WorkspaceSQLiteStoreBackendFactoryTests {
    @Test("corrupt core SQLite is quarantined and recreated before legacy workspace import")
    func corruptCoreSQLiteIsQuarantinedAndRecreatedBeforeLegacyWorkspaceImport() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-sqlite-factory-\(UUID().uuidString)")
        let workspacesDirectory = rootDirectory.appending(path: "workspaces")
        let coreSQLiteURL = rootDirectory.appending(path: "core.sqlite")
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        try Data("not a sqlite database".utf8).write(to: coreSQLiteURL)

        let workspaceId = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_001_000)
        let pane = Pane(
            content: .terminal(.init(provider: .zmx, lifetime: .persistent)),
            metadata: .init(
                source: .floating(launchDirectory: nil, title: nil),
                createdAt: createdAt,
                title: "Legacy After Corruption"
            )
        )
        let tab = Tab(paneId: pane.id, name: "Imported Tab")
        let legacyPersistor = WorkspacePersistor(workspacesDir: workspacesDirectory)
        #expect(legacyPersistor.ensureDirectory())
        try legacyPersistor.save(
            .init(
                id: workspaceId,
                name: "Legacy Reimport Workspace",
                panes: [pane],
                tabs: [tab],
                activeTabId: tab.id,
                createdAt: createdAt,
                updatedAt: Date(timeIntervalSince1970: 1_700_001_100)
            )
        )

        var recoveryEvents: [PersistenceRecoveryEvent] = []
        let factory = WorkspaceSQLiteStoreBackendFactory(
            coreDatabaseURL: coreSQLiteURL,
            localDatabaseURL: { workspaceId in
                rootDirectory.appending(path: "\(workspaceId.uuidString).local.sqlite")
            },
            recoveryReporter: { event in recoveryEvents.append(event) }
        )

        let backend = try #require(factory.makeBackend())
        let store = WorkspaceStore(
            persistor: legacyPersistor,
            sqliteBackend: backend,
            recoveryReporter: { event in recoveryEvents.append(event) }
        )

        store.restore()

        #expect(store.identityAtom.workspaceId == workspaceId)
        #expect(store.identityAtom.workspaceName == "Legacy Reimport Workspace")
        #expect(store.paneAtom.pane(pane.id)?.title == "Legacy After Corruption")
        #expect(try backend.coreRepository.fetchWorkspace(id: workspaceId)?.name == "Legacy Reimport Workspace")
        #expect(
            recoveryEvents.contains { event in
                event.store == .workspace
                    && event.recovery == .quarantinedAndReset
                    && event.quarantinedFilename?.contains("core.sqlite.corrupt-") == true
            }
        )
        #expect(FileManager.default.fileExists(atPath: coreSQLiteURL.path))
    }
}
