import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("WorkspaceCoreTabGraphLayoutRepairMigrationTests")
struct WorkspaceCoreTabGraphLayoutRepairMigrationTests {
    @Test("drawer view layout row kind rejects unknown storage values")
    func drawerViewLayoutRowKindRejectsUnknownStorageValues() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceCoreMigrations.migrate(databaseQueue)
        let fixture = TabGraphStorageFixture()

        expectDatabaseError(containing: "drawer view layout row_kind must be top or bottom") {
            try databaseQueue.write { database in
                try seedTabGraphStorageFixture(database, fixture: fixture)
                try database.execute(
                    sql: """
                        INSERT INTO drawer_view_layout_pane(
                            arrangement_id, drawer_id, row_kind, pane_id, sort_index, ratio
                        )
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        fixture.arrangementId,
                        fixture.drawerId,
                        "diagonal",
                        fixture.drawerPaneId,
                        0,
                        1.0,
                    ]
                )
            }
        }
    }

    @Test("layout storage repair migration repairs stale dividers and installs guards")
    func layoutStorageRepairMigrationRepairsStaleDividersAndInstallsGuards() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        let fixture = TabGraphStorageFixture()

        try WorkspaceCoreMigrations.migrator.migrate(
            databaseQueue,
            upTo: "004_create_tabs_and_arrangements"
        )
        try databaseQueue.write { database in
            try seedLegacyCorruptTabGraphStorage(database, fixture: fixture)
        }

        try WorkspaceCoreMigrations.migrate(databaseQueue)

        let repairCounts = try databaseQueue.read { database in
            try fetchTabGraphStorageRepairCounts(database)
        }
        #expect(repairCounts.arrangementDividers == 0)
        #expect(repairCounts.drawerDividers == 0)
        #expect(repairCounts.invalidDrawerPaneRows == 0)
        #expect(repairCounts.invalidDrawerDividerRows == 0)
        expectDatabaseError(containing: "drawer view layout row_kind must be top or bottom") {
            try databaseQueue.write { database in
                try database.execute(
                    sql: """
                        INSERT INTO drawer_view_layout_divider(
                            arrangement_id, drawer_id, row_kind, divider_id, sort_index
                        )
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        fixture.arrangementId,
                        fixture.drawerId,
                        "sideways",
                        UUID().uuidString,
                        0,
                    ]
                )
            }
        }
    }

    @Test("layout storage repair migration preserves adjacent divider identity")
    func layoutStorageRepairMigrationPreservesAdjacentDividerIdentity() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        let fixture = TabGraphStorageFixture()
        let layoutSecondPaneId = UUID().uuidString
        let drawerSecondPaneId = UUID().uuidString
        let staleArrangementDividerId = UUID().uuidString
        let retainedArrangementDividerId = UUID().uuidString
        let staleDrawerDividerId = UUID().uuidString
        let retainedDrawerDividerId = UUID().uuidString

        try WorkspaceCoreMigrations.migrator.migrate(
            databaseQueue,
            upTo: "004_create_tabs_and_arrangements"
        )
        try databaseQueue.write { database in
            try seedTabGraphStorageFixture(database, fixture: fixture)
            try insertPane(database, workspaceId: fixture.workspaceId, paneId: layoutSecondPaneId)
            try insertPane(
                database,
                workspaceId: fixture.workspaceId,
                paneId: drawerSecondPaneId,
                parentPaneId: fixture.parentPaneId
            )
            try insertArrangementLayoutPane(
                database,
                arrangementId: fixture.arrangementId,
                paneId: fixture.parentPaneId,
                sortIndex: 1
            )
            try insertArrangementLayoutPane(
                database,
                arrangementId: fixture.arrangementId,
                paneId: layoutSecondPaneId,
                sortIndex: 2
            )
            try insertArrangementLayoutDivider(
                database,
                arrangementId: fixture.arrangementId,
                dividerId: staleArrangementDividerId,
                sortIndex: 0
            )
            try insertArrangementLayoutDivider(
                database,
                arrangementId: fixture.arrangementId,
                dividerId: retainedArrangementDividerId,
                sortIndex: 1
            )
            try insertDrawerViewLayoutPane(
                database,
                fixture: fixture,
                rowKind: "top",
                paneId: fixture.drawerPaneId,
                sortIndex: 1
            )
            try insertDrawerViewLayoutPane(
                database,
                fixture: fixture,
                rowKind: "top",
                paneId: drawerSecondPaneId,
                sortIndex: 2
            )
            try insertDrawerViewLayoutDivider(
                database,
                fixture: fixture,
                rowKind: "top",
                dividerId: staleDrawerDividerId,
                sortIndex: 0
            )
            try insertDrawerViewLayoutDivider(
                database,
                fixture: fixture,
                rowKind: "top",
                dividerId: retainedDrawerDividerId,
                sortIndex: 1
            )
        }

        try WorkspaceCoreMigrations.migrate(databaseQueue)

        let retainedDividerIds = try databaseQueue.read { database in
            try fetchRetainedLayoutDividerIds(database)
        }
        #expect(retainedDividerIds.arrangementDividerIds == [retainedArrangementDividerId])
        #expect(retainedDividerIds.drawerDividerIds == [retainedDrawerDividerId])
    }

    private struct TabGraphStorageFixture {
        let workspaceId = UUID().uuidString
        let tabId = UUID().uuidString
        let arrangementId = UUID().uuidString
        let parentPaneId = UUID().uuidString
        let drawerPaneId = UUID().uuidString
        let invalidDrawerPaneId = UUID().uuidString
        let drawerId = UUID().uuidString
    }

    private struct TabGraphStorageRepairCounts {
        let arrangementDividers: Int
        let drawerDividers: Int
        let invalidDrawerPaneRows: Int
        let invalidDrawerDividerRows: Int
    }

    private struct RetainedLayoutDividerIds {
        let arrangementDividerIds: [String]
        let drawerDividerIds: [String]
    }

    private func expectDatabaseError(
        containing expectedMessage: String,
        _ operation: () throws -> Void
    ) {
        do {
            try operation()
            Issue.record("Expected DatabaseError containing '\(expectedMessage)'")
        } catch let error as DatabaseError {
            #expect(error.message?.contains(expectedMessage) == true)
        } catch {
            Issue.record("Expected DatabaseError containing '\(expectedMessage)', got \(error)")
        }
    }

    private func seedTabGraphStorageFixture(
        _ database: Database,
        fixture: TabGraphStorageFixture
    ) throws {
        try insertWorkspace(database, workspaceId: fixture.workspaceId)
        try insertPane(database, workspaceId: fixture.workspaceId, paneId: fixture.parentPaneId)
        try insertPane(
            database,
            workspaceId: fixture.workspaceId,
            paneId: fixture.drawerPaneId,
            parentPaneId: fixture.parentPaneId
        )
        try insertTabShell(database, fixture: fixture)
        try insertTabArrangement(database, fixture: fixture)
        try insertDrawer(database, fixture: fixture)
        try insertArrangementDrawerView(database, fixture: fixture)
    }

    private func seedLegacyCorruptTabGraphStorage(
        _ database: Database,
        fixture: TabGraphStorageFixture
    ) throws {
        try seedTabGraphStorageFixture(database, fixture: fixture)
        try insertPane(
            database,
            workspaceId: fixture.workspaceId,
            paneId: fixture.invalidDrawerPaneId,
            parentPaneId: fixture.parentPaneId
        )
        try insertArrangementLayoutPane(database, fixture: fixture)
        try insertArrangementLayoutDivider(database, fixture: fixture)
        try insertDrawerViewLayoutPane(
            database,
            fixture: fixture,
            rowKind: "top",
            paneId: fixture.drawerPaneId,
            sortIndex: 1
        )
        try insertDrawerViewLayoutDivider(database, fixture: fixture, rowKind: "top", sortIndex: 2)
        try insertDrawerViewLayoutPane(
            database,
            fixture: fixture,
            rowKind: "diagonal",
            paneId: fixture.invalidDrawerPaneId,
            sortIndex: 0
        )
        try insertDrawerViewLayoutDivider(database, fixture: fixture, rowKind: "sideways", sortIndex: 0)
    }

    private func insertWorkspace(_ database: Database, workspaceId: String) throws {
        try database.execute(
            sql: "INSERT INTO workspace(id, name, created_at, updated_at) VALUES (?, ?, ?, ?)",
            arguments: [workspaceId, "SQLite Workspace", 1.0, 1.0]
        )
    }

    private func insertPane(
        _ database: Database,
        workspaceId: String,
        paneId: String,
        parentPaneId: String? = nil
    ) throws {
        if try paneTableColumnNames(database).contains("source_kind") {
            try insertLegacySourcePane(
                database,
                workspaceId: workspaceId,
                paneId: paneId,
                parentPaneId: parentPaneId
            )
        } else {
            try insertFacetPane(database, workspaceId: workspaceId, paneId: paneId, parentPaneId: parentPaneId)
        }
    }

    private func paneTableColumnNames(_ database: Database) throws -> Set<String> {
        let rows = try Row.fetchAll(database, sql: "PRAGMA table_info(pane)")
        return Set(rows.compactMap { row in row["name"] as String? })
    }

    private func insertLegacySourcePane(
        _ database: Database,
        workspaceId: String,
        paneId: String,
        parentPaneId: String?
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO pane(
                    id, workspace_id, content_type, execution_backend, source_kind,
                    source_repo_id, source_worktree_id, launch_directory, title, cwd,
                    residency_kind, kind, parent_pane_id, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                paneId,
                workspaceId,
                SQLitePaneContentTypeStorage.storageValue(for: .terminal),
                "zmx",
                "workspace",
                nil,
                nil,
                "/tmp",
                "Terminal",
                "/tmp",
                "active",
                parentPaneId == nil ? "leaf" : "drawerChild",
                parentPaneId,
                1.0,
                1.0,
            ]
        )
    }

    private func insertFacetPane(
        _ database: Database,
        workspaceId: String,
        paneId: String,
        parentPaneId: String?
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
                parentPaneId == nil ? "leaf" : "drawerChild",
                parentPaneId,
                1.0,
                1.0,
            ]
        )
    }

    private func insertTabShell(_ database: Database, fixture: TabGraphStorageFixture) throws {
        try database.execute(
            sql: "INSERT INTO tab_shell(id, workspace_id, name, sort_index) VALUES (?, ?, ?, ?)",
            arguments: [fixture.tabId, fixture.workspaceId, "Main", 0]
        )
    }

    private func insertTabArrangement(_ database: Database, fixture: TabGraphStorageFixture) throws {
        try database.execute(
            sql: """
                INSERT INTO tab_arrangement(id, tab_id, name, is_default, shows_minimized_panes, sort_index)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [fixture.arrangementId, fixture.tabId, "Default", 1, 0, 0]
        )
    }

    private func insertArrangementLayoutPane(_ database: Database, fixture: TabGraphStorageFixture) throws {
        try insertArrangementLayoutPane(
            database,
            arrangementId: fixture.arrangementId,
            paneId: fixture.parentPaneId,
            sortIndex: 1
        )
    }

    private func insertArrangementLayoutPane(
        _ database: Database,
        arrangementId: String,
        paneId: String,
        sortIndex: Int
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO arrangement_layout_pane(arrangement_id, pane_id, sort_index, ratio)
                VALUES (?, ?, ?, ?)
                """,
            arguments: [arrangementId, paneId, sortIndex, 1.0]
        )
    }

    private func insertArrangementLayoutDivider(_ database: Database, fixture: TabGraphStorageFixture) throws {
        try insertArrangementLayoutDivider(
            database,
            arrangementId: fixture.arrangementId,
            dividerId: UUID().uuidString,
            sortIndex: 2
        )
    }

    private func insertArrangementLayoutDivider(
        _ database: Database,
        arrangementId: String,
        dividerId: String,
        sortIndex: Int
    ) throws {
        try database.execute(
            sql: "INSERT INTO arrangement_layout_divider(arrangement_id, divider_id, sort_index) VALUES (?, ?, ?)",
            arguments: [arrangementId, dividerId, sortIndex]
        )
    }

    private func insertDrawer(_ database: Database, fixture: TabGraphStorageFixture) throws {
        try database.execute(
            sql: "INSERT INTO drawer(id, parent_pane_id) VALUES (?, ?)",
            arguments: [fixture.drawerId, fixture.parentPaneId]
        )
    }

    private func insertArrangementDrawerView(_ database: Database, fixture: TabGraphStorageFixture) throws {
        try database.execute(
            sql: "INSERT INTO arrangement_drawer_view(arrangement_id, drawer_id, row_split_ratio) VALUES (?, ?, ?)",
            arguments: [fixture.arrangementId, fixture.drawerId, 0.5]
        )
    }

    private func insertDrawerViewLayoutPane(
        _ database: Database,
        fixture: TabGraphStorageFixture,
        rowKind: String,
        paneId: String,
        sortIndex: Int
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO drawer_view_layout_pane(
                    arrangement_id, drawer_id, row_kind, pane_id, sort_index, ratio
                )
                VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [fixture.arrangementId, fixture.drawerId, rowKind, paneId, sortIndex, 1.0]
        )
    }

    private func insertDrawerViewLayoutDivider(
        _ database: Database,
        fixture: TabGraphStorageFixture,
        rowKind: String,
        sortIndex: Int
    ) throws {
        try insertDrawerViewLayoutDivider(
            database,
            fixture: fixture,
            rowKind: rowKind,
            dividerId: UUID().uuidString,
            sortIndex: sortIndex
        )
    }

    private func insertDrawerViewLayoutDivider(
        _ database: Database,
        fixture: TabGraphStorageFixture,
        rowKind: String,
        dividerId: String,
        sortIndex: Int
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO drawer_view_layout_divider(
                    arrangement_id, drawer_id, row_kind, divider_id, sort_index
                )
                VALUES (?, ?, ?, ?, ?)
                """,
            arguments: [fixture.arrangementId, fixture.drawerId, rowKind, dividerId, sortIndex]
        )
    }

    private func fetchRetainedLayoutDividerIds(_ database: Database) throws -> RetainedLayoutDividerIds {
        try .init(
            arrangementDividerIds: String.fetchAll(
                database,
                sql: "SELECT divider_id FROM arrangement_layout_divider ORDER BY sort_index"
            ),
            drawerDividerIds: String.fetchAll(
                database,
                sql: """
                    SELECT divider_id
                    FROM drawer_view_layout_divider
                    WHERE row_kind = 'top'
                    ORDER BY sort_index
                    """
            )
        )
    }

    private func fetchTabGraphStorageRepairCounts(_ database: Database) throws -> TabGraphStorageRepairCounts {
        try .init(
            arrangementDividers: Int.fetchOne(database, sql: "SELECT COUNT(*) FROM arrangement_layout_divider") ?? 0,
            drawerDividers: Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM drawer_view_layout_divider WHERE row_kind = 'top'"
            ) ?? 0,
            invalidDrawerPaneRows: Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM drawer_view_layout_pane WHERE row_kind NOT IN ('top', 'bottom')"
            ) ?? 0,
            invalidDrawerDividerRows: Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM drawer_view_layout_divider WHERE row_kind NOT IN ('top', 'bottom')"
            ) ?? 0
        )
    }
}
