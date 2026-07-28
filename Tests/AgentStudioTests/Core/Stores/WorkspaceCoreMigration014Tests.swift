import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("WorkspaceCoreMigration014Tests")
struct WorkspaceCoreMigration014Tests {
    @Test("migration 014 discards minimized visibility authority and preserves arrangement constraints")
    func migration014DiscardsMinimizedVisibilityAuthorityAndPreservesArrangementConstraints() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.temporaryDirectory) }

        try await seedMigration013Fixture(fixture)
        try migrateFixtureToLatestSchema(fixture)

        let datastoreFactory = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: fixture.coreDatabaseURL,
            localDatabaseURL: fixture.localDatabaseURL
        )
        let datastore = datastoreFactory.makeDatastore()
        let loadResult = await datastore.loadWorkspaceSnapshot()
        guard case .loaded(let loadedSnapshot) = loadResult else {
            Issue.record("Expected migration 014 fixture to load, got \(loadResult)")
            return
        }
        let loadedTab = try #require(loadedSnapshot.tabs.single)
        let loadedDefaultCandidate = loadedTab.arrangements.first { $0.isDefault }
        let loadedDefault = try #require(loadedDefaultCandidate)
        #expect(loadedTab.allPaneIds == [fixture.firstPaneId, fixture.secondPaneId])
        #expect(Set(loadedDefault.layout.paneIds) == [fixture.firstPaneId, fixture.secondPaneId])
        #expect(loadedDefault.minimizedPaneIds.isEmpty)
        #expect(loadedTab.arrangements.contains(where: { $0.id == fixture.userArrangementId }))

        try await datastore.saveWorkspaceSnapshotBundle(.init(workspace: loadedSnapshot))
        let reloadedDatastore = datastoreFactory.makeDatastore()
        let reloadResult = await reloadedDatastore.loadWorkspaceSnapshot()
        guard case .loaded(let reloadedSnapshot) = reloadResult else {
            Issue.record("Expected saved migration 014 fixture to reload, got \(reloadResult)")
            return
        }
        let reloadedTab = try #require(reloadedSnapshot.tabs.single)
        let reloadedDefaultCandidate = reloadedTab.arrangements.first { $0.isDefault }
        let reloadedDefault = try #require(reloadedDefaultCandidate)
        #expect(Set(reloadedDefault.layout.paneIds) == [fixture.firstPaneId, fixture.secondPaneId])
        #expect(reloadedDefault.minimizedPaneIds.isEmpty)

        try await verifyMigratedSchemaConstraintsAndCascade(fixture)
    }

    private func makeFixture() throws -> Migration014Fixture {
        let temporaryDirectory = FileManager.default.temporaryDirectory.appending(
            path: "agentstudio-core-migration-014-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        return Migration014Fixture(
            temporaryDirectory: temporaryDirectory,
            coreDatabaseURL: temporaryDirectory.appending(path: "core.sqlite"),
            localDatabaseURL: temporaryDirectory.appending(path: "local.sqlite"),
            workspaceId: UUID(),
            tabId: UUID(),
            firstPaneId: UUID(),
            secondPaneId: UUID(),
            defaultArrangementId: UUID(),
            userArrangementId: UUID()
        )
    }

    private func seedMigration013Fixture(_ fixture: Migration014Fixture) async throws {
        let seedPool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: fixture.coreDatabaseURL,
            label: "AgentStudio.sqlite.migration-014.seed"
        )
        try WorkspaceCoreMigrations.migrator.migrate(
            seedPool,
            upTo: "013_globalize_repository_topology"
        )
        try await seedPool.write { database in
            try insertMigration013Rows(database, fixture: fixture)
        }
        try seedPool.close()
    }

    private func insertMigration013Rows(
        _ database: Database,
        fixture: Migration014Fixture
    ) throws {
        try insertWorkspace(database, workspaceId: fixture.workspaceId.uuidString)
        try database.execute(
            sql: "UPDATE app_workspace_selection SET active_workspace_id = ? WHERE singleton_id = 1",
            arguments: [fixture.workspaceId.uuidString]
        )
        for paneId in [fixture.firstPaneId, fixture.secondPaneId] {
            try insertPane(database, workspaceId: fixture.workspaceId.uuidString, paneId: paneId.uuidString)
            try database.execute(
                sql: "UPDATE pane SET execution_backend = ? WHERE id = ?",
                arguments: ["local", paneId.uuidString]
            )
            try insertDrawer(database, drawerId: UUID().uuidString, parentPaneId: paneId.uuidString)
            try database.execute(
                sql: """
                    INSERT INTO pane_content_terminal(pane_id, provider, lifetime, zmx_session_id)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [paneId.uuidString, "zmx", "persistent", "session-\(paneId.uuidString)"]
            )
        }
        try insertTabShell(database, fixture: fixture)
        try insertTabPane(
            database,
            tabId: fixture.tabId.uuidString,
            paneId: fixture.firstPaneId.uuidString,
            sortIndex: 0
        )
        try insertTabPane(
            database,
            tabId: fixture.tabId.uuidString,
            paneId: fixture.secondPaneId.uuidString,
            sortIndex: 1
        )
        try insertLegacyTabArrangement(
            database,
            props: LegacyTabArrangementInsertProps(
                tabId: fixture.tabId.uuidString,
                arrangementId: fixture.defaultArrangementId.uuidString,
                name: "Default",
                isDefault: true,
                showsMinimizedPanes: false,
                sortIndex: 0
            )
        )
        try insertLegacyTabArrangement(
            database,
            props: LegacyTabArrangementInsertProps(
                tabId: fixture.tabId.uuidString,
                arrangementId: fixture.userArrangementId.uuidString,
                name: "Layout 1",
                isDefault: false,
                showsMinimizedPanes: true,
                sortIndex: 1
            )
        )
        try insertArrangementRows(database, fixture: fixture)
    }

    private func insertArrangementRows(
        _ database: Database,
        fixture: Migration014Fixture
    ) throws {
        for (sortIndex, paneId) in [fixture.firstPaneId, fixture.secondPaneId].enumerated() {
            try database.execute(
                sql: """
                    INSERT INTO arrangement_layout_pane(arrangement_id, pane_id, sort_index, ratio)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [fixture.defaultArrangementId.uuidString, paneId.uuidString, sortIndex, 0.5]
            )
        }
        try database.execute(
            sql: """
                INSERT INTO arrangement_layout_divider(arrangement_id, divider_id, sort_index)
                VALUES (?, ?, ?)
                """,
            arguments: [fixture.defaultArrangementId.uuidString, UUID().uuidString, 0]
        )
        try database.execute(
            sql: """
                INSERT INTO arrangement_layout_pane(arrangement_id, pane_id, sort_index, ratio)
                VALUES (?, ?, ?, ?)
                """,
            arguments: [fixture.userArrangementId.uuidString, fixture.firstPaneId.uuidString, 0, 1.0]
        )
        try database.execute(
            sql: """
                INSERT INTO arrangement_minimized_pane(arrangement_id, pane_id)
                VALUES (?, ?)
                """,
            arguments: [fixture.defaultArrangementId.uuidString, fixture.secondPaneId.uuidString]
        )
    }

    private func migrateFixtureToLatestSchema(_ fixture: Migration014Fixture) throws {
        let migrationPool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: fixture.coreDatabaseURL,
            label: "AgentStudio.sqlite.migration-014.migrate"
        )
        try WorkspaceCoreMigrations.migrate(migrationPool)
        try migrationPool.close()
    }

    private func verifyMigratedSchemaConstraintsAndCascade(
        _ fixture: Migration014Fixture
    ) async throws {
        let verificationPool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: fixture.coreDatabaseURL,
            label: "AgentStudio.sqlite.migration-014.verify"
        )
        let arrangementColumns = try await verificationPool.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(tab_arrangement)")
                .map { row in row["name"] as String }
        }
        #expect(!arrangementColumns.contains("shows_minimized_panes"))

        try await assertSecondDefaultIsRejected(verificationPool, fixture: fixture)

        let cascadeCounts = try await verificationPool.write { database in
            let beforeDelete = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM arrangement_layout_pane WHERE arrangement_id = ?",
                arguments: [fixture.userArrangementId.uuidString]
            )
            try database.execute(
                sql: "DELETE FROM tab_arrangement WHERE id = ?",
                arguments: [fixture.userArrangementId.uuidString]
            )
            let afterDelete = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM arrangement_layout_pane WHERE arrangement_id = ?",
                arguments: [fixture.userArrangementId.uuidString]
            )
            return (beforeDelete, afterDelete)
        }
        #expect(cascadeCounts == (1, 0))
        try verificationPool.close()
    }

    private func assertSecondDefaultIsRejected(
        _ verificationPool: DatabasePool,
        fixture: Migration014Fixture
    ) async throws {
        do {
            try await verificationPool.write { database in
                try insertTabArrangement(
                    database,
                    tabId: fixture.tabId.uuidString,
                    arrangementId: UUID().uuidString,
                    name: "Also Default",
                    isDefault: true,
                    sortIndex: 2
                )
            }
            Issue.record("Expected one-default unique index to reject a second Default")
        } catch let error as DatabaseError {
            #expect(error.message?.contains("UNIQUE constraint failed: tab_arrangement.tab_id") == true)
        } catch {
            Issue.record("Expected DatabaseError for a second Default, got \(error)")
        }
    }

    private func insertWorkspace(_ database: Database, workspaceId: String) throws {
        try database.execute(
            sql: """
                INSERT INTO workspace(id, name, created_at, updated_at)
                VALUES (?, ?, ?, ?)
                """,
            arguments: [workspaceId, "SQLite Workspace", 1.0, 1.0]
        )
    }

    private func insertPane(
        _ database: Database,
        workspaceId: String,
        paneId: String
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO pane(
                    id, workspace_id, content_type, execution_backend,
                    facet_repo_id, facet_worktree_id, launch_directory, title, cwd,
                    residency_kind, kind, parent_pane_id, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                paneId,
                workspaceId,
                SQLitePaneContentTypeStorage.storageValue(for: .terminal),
                "zmx",
                nil,
                nil,
                "/tmp",
                "Terminal",
                "/tmp",
                "active",
                "leaf",
                nil,
                1.0,
                1.0,
            ]
        )
    }

    private func insertDrawer(
        _ database: Database,
        drawerId: String,
        parentPaneId: String
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO drawer(id, parent_pane_id)
                VALUES (?, ?)
                """,
            arguments: [drawerId, parentPaneId]
        )
    }

    private func insertTabShell(
        _ database: Database,
        fixture: Migration014Fixture
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO tab_shell(id, workspace_id, name, sort_index)
                VALUES (?, ?, ?, ?)
                """,
            arguments: [fixture.tabId.uuidString, fixture.workspaceId.uuidString, "Migrated Tab", 0]
        )
    }

    private func insertTabPane(
        _ database: Database,
        tabId: String,
        paneId: String,
        sortIndex: Int
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO tab_pane(tab_id, pane_id, sort_index)
                VALUES (?, ?, ?)
                """,
            arguments: [tabId, paneId, sortIndex]
        )
    }

    private func insertLegacyTabArrangement(
        _ database: Database,
        props: LegacyTabArrangementInsertProps
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO tab_arrangement(id, tab_id, name, is_default, shows_minimized_panes, sort_index)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                props.arrangementId,
                props.tabId,
                props.name,
                props.isDefault ? 1 : 0,
                props.showsMinimizedPanes ? 1 : 0,
                props.sortIndex,
            ]
        )
    }

    private func insertTabArrangement(
        _ database: Database,
        tabId: String,
        arrangementId: String,
        name: String,
        isDefault: Bool,
        sortIndex: Int
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO tab_arrangement(id, tab_id, name, is_default, sort_index)
                VALUES (?, ?, ?, ?, ?)
                """,
            arguments: [arrangementId, tabId, name, isDefault ? 1 : 0, sortIndex]
        )
    }
}

private struct Migration014Fixture {
    let temporaryDirectory: URL
    let coreDatabaseURL: URL
    let localDatabaseURL: URL
    let workspaceId: UUID
    let tabId: UUID
    let firstPaneId: UUID
    let secondPaneId: UUID
    let defaultArrangementId: UUID
    let userArrangementId: UUID
}

private struct LegacyTabArrangementInsertProps {
    let tabId: String
    let arrangementId: String
    let name: String
    let isDefault: Bool
    let showsMinimizedPanes: Bool
    let sortIndex: Int
}
