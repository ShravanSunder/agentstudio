import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("WorkspaceCorePaneLinkMigrationTests")
struct WorkspaceCorePaneLinkMigrationTests {
    @Test("tab pane membership rejects panes from different workspace")
    func tabPaneMembershipRejectsPanesFromDifferentWorkspace() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceCoreMigrations.migrate(databaseQueue)
        let tabWorkspaceId = UUID().uuidString
        let paneWorkspaceId = UUID().uuidString
        let tabId = UUID().uuidString
        let paneId = UUID().uuidString

        expectDatabaseError(containing: "tab_pane pane must belong to tab workspace") {
            try databaseQueue.write { database in
                try insertWorkspace(database, workspaceId: tabWorkspaceId)
                try insertWorkspace(database, workspaceId: paneWorkspaceId)
                try insertTabShell(database, workspaceId: tabWorkspaceId, tabId: tabId)
                try insertPane(database, workspaceId: paneWorkspaceId, paneId: paneId)
                try insertTabPane(database, tabId: tabId, paneId: paneId)
            }
        }
    }

    @Test("pane parent link rejects parent from different workspace")
    func paneParentLinkRejectsParentFromDifferentWorkspace() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceCoreMigrations.migrate(databaseQueue)
        let parentWorkspaceId = UUID().uuidString
        let childWorkspaceId = UUID().uuidString
        let parentPaneId = UUID().uuidString
        let childPaneId = UUID().uuidString

        expectDatabaseError(containing: "pane parent_pane_id must belong to pane workspace") {
            try databaseQueue.write { database in
                try insertWorkspace(database, workspaceId: parentWorkspaceId)
                try insertWorkspace(database, workspaceId: childWorkspaceId)
                try insertPane(database, workspaceId: parentWorkspaceId, paneId: parentPaneId)
                try insertPane(
                    database,
                    workspaceId: childWorkspaceId,
                    paneId: childPaneId,
                    parentPaneId: parentPaneId
                )
            }
        }
    }

    @Test("drawer pane membership rejects panes from different workspace")
    func drawerPaneMembershipRejectsPanesFromDifferentWorkspace() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceCoreMigrations.migrate(databaseQueue)
        let drawerWorkspaceId = UUID().uuidString
        let childWorkspaceId = UUID().uuidString
        let parentPaneId = UUID().uuidString
        let childPaneId = UUID().uuidString
        let drawerId = UUID().uuidString

        expectDatabaseError(containing: "drawer_pane pane must belong to drawer workspace") {
            try databaseQueue.write { database in
                try insertWorkspace(database, workspaceId: drawerWorkspaceId)
                try insertWorkspace(database, workspaceId: childWorkspaceId)
                try insertPane(database, workspaceId: drawerWorkspaceId, paneId: parentPaneId)
                try insertPane(database, workspaceId: childWorkspaceId, paneId: childPaneId)
                try insertDrawer(database, drawerId: drawerId, parentPaneId: parentPaneId)
                try insertDrawerPane(database, drawerId: drawerId, paneId: childPaneId)
            }
        }
    }

    @Test("arrangement layout rows reject panes from different workspace")
    func arrangementLayoutRowsRejectPanesFromDifferentWorkspace() throws {
        let ids = ArrangementFixtureIds()
        try expectArrangementPaneError(
            ids: ids,
            expectedMessage: "arrangement_layout_pane pane must belong to arrangement workspace"
        ) { database in
            try insertArrangementLayoutPane(database, arrangementId: ids.arrangementId, paneId: ids.foreignPaneId)
        }
    }

    @Test("arrangement minimized rows reject panes from different workspace")
    func arrangementMinimizedRowsRejectPanesFromDifferentWorkspace() throws {
        let ids = ArrangementFixtureIds()
        try expectArrangementPaneError(
            ids: ids,
            expectedMessage: "arrangement_minimized_pane pane must belong to arrangement workspace"
        ) { database in
            try database.execute(
                sql: """
                    INSERT INTO arrangement_minimized_pane(arrangement_id, pane_id)
                    VALUES (?, ?)
                    """,
                arguments: [ids.arrangementId, ids.foreignPaneId]
            )
        }
    }

    @Test("arrangement drawer view rejects drawers from different workspace")
    func arrangementDrawerViewRejectsDrawersFromDifferentWorkspace() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceCoreMigrations.migrate(databaseQueue)
        let arrangementWorkspaceId = UUID().uuidString
        let drawerWorkspaceId = UUID().uuidString
        let tabId = UUID().uuidString
        let arrangementId = UUID().uuidString
        let parentPaneId = UUID().uuidString
        let drawerId = UUID().uuidString

        expectDatabaseError(containing: "arrangement_drawer_view drawer must belong to arrangement workspace") {
            try databaseQueue.write { database in
                try insertWorkspace(database, workspaceId: arrangementWorkspaceId)
                try insertWorkspace(database, workspaceId: drawerWorkspaceId)
                try insertTabShell(database, workspaceId: arrangementWorkspaceId, tabId: tabId)
                try insertTabArrangement(database, tabId: tabId, arrangementId: arrangementId)
                try insertPane(database, workspaceId: drawerWorkspaceId, paneId: parentPaneId)
                try insertDrawer(database, drawerId: drawerId, parentPaneId: parentPaneId)
                try insertArrangementDrawerView(database, arrangementId: arrangementId, drawerId: drawerId)
            }
        }
    }

    @Test("drawer view layout rows reject panes from different workspace")
    func drawerViewLayoutRowsRejectPanesFromDifferentWorkspace() throws {
        let ids = DrawerViewFixtureIds()
        try expectDrawerViewPaneError(
            ids: ids,
            expectedMessage: "drawer_view_layout_pane pane must belong to arrangement workspace"
        ) { database in
            try database.execute(
                sql: """
                    INSERT INTO drawer_view_layout_pane(
                        arrangement_id, drawer_id, row_kind, pane_id, sort_index, ratio
                    )
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [ids.arrangementId, ids.drawerId, "top", ids.foreignPaneId, 0, 1.0]
            )
        }
    }

    @Test("drawer view minimized rows reject panes from different workspace")
    func drawerViewMinimizedRowsRejectPanesFromDifferentWorkspace() throws {
        let ids = DrawerViewFixtureIds()
        try expectDrawerViewPaneError(
            ids: ids,
            expectedMessage: "drawer_view_minimized_pane pane must belong to arrangement workspace"
        ) { database in
            try database.execute(
                sql: """
                    INSERT INTO drawer_view_minimized_pane(arrangement_id, drawer_id, pane_id)
                    VALUES (?, ?, ?)
                    """,
                arguments: [ids.arrangementId, ids.drawerId, ids.foreignPaneId]
            )
        }
    }

    private func expectArrangementPaneError(
        ids: ArrangementFixtureIds,
        expectedMessage: String,
        operation: (Database) throws -> Void
    ) throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceCoreMigrations.migrate(databaseQueue)

        expectDatabaseError(containing: expectedMessage) {
            try databaseQueue.write { database in
                try insertArrangementFixture(database, ids: ids)
                try operation(database)
            }
        }
    }

    private func expectDrawerViewPaneError(
        ids: DrawerViewFixtureIds,
        expectedMessage: String,
        operation: (Database) throws -> Void
    ) throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceCoreMigrations.migrate(databaseQueue)

        expectDatabaseError(containing: expectedMessage) {
            try databaseQueue.write { database in
                try insertDrawerViewFixture(database, ids: ids)
                try operation(database)
            }
        }
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

    private func insertArrangementFixture(_ database: Database, ids: ArrangementFixtureIds) throws {
        try insertWorkspace(database, workspaceId: ids.arrangementWorkspaceId)
        try insertWorkspace(database, workspaceId: ids.foreignPaneWorkspaceId)
        try insertTabShell(database, workspaceId: ids.arrangementWorkspaceId, tabId: ids.tabId)
        try insertTabArrangement(database, tabId: ids.tabId, arrangementId: ids.arrangementId)
        try insertPane(database, workspaceId: ids.foreignPaneWorkspaceId, paneId: ids.foreignPaneId)
    }

    private func insertDrawerViewFixture(_ database: Database, ids: DrawerViewFixtureIds) throws {
        try insertWorkspace(database, workspaceId: ids.arrangementWorkspaceId)
        try insertWorkspace(database, workspaceId: ids.foreignPaneWorkspaceId)
        try insertTabShell(database, workspaceId: ids.arrangementWorkspaceId, tabId: ids.tabId)
        try insertTabArrangement(database, tabId: ids.tabId, arrangementId: ids.arrangementId)
        try insertPane(database, workspaceId: ids.arrangementWorkspaceId, paneId: ids.parentPaneId)
        try insertPane(database, workspaceId: ids.foreignPaneWorkspaceId, paneId: ids.foreignPaneId)
        try insertDrawer(database, drawerId: ids.drawerId, parentPaneId: ids.parentPaneId)
        try insertArrangementDrawerView(database, arrangementId: ids.arrangementId, drawerId: ids.drawerId)
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
        paneId: String,
        parentPaneId: String? = nil
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO pane(
                    id, workspace_id, content_type, execution_backend,
                    launch_directory, title, cwd, residency_kind, kind, parent_pane_id,
                    created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                paneId,
                workspaceId,
                SQLitePaneContentTypeStorage.storageValue(for: .terminal),
                "zmx",
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

    private func insertTabShell(_ database: Database, workspaceId: String, tabId: String) throws {
        try database.execute(
            sql: """
                INSERT INTO tab_shell(id, workspace_id, name, sort_index)
                VALUES (?, ?, ?, ?)
                """,
            arguments: [tabId, workspaceId, "First", 0]
        )
    }

    private func insertTabPane(_ database: Database, tabId: String, paneId: String) throws {
        try database.execute(
            sql: """
                INSERT INTO tab_pane(tab_id, pane_id, sort_index)
                VALUES (?, ?, ?)
                """,
            arguments: [tabId, paneId, 0]
        )
    }

    private func insertTabArrangement(_ database: Database, tabId: String, arrangementId: String) throws {
        try database.execute(
            sql: """
                INSERT INTO tab_arrangement(id, tab_id, name, is_default, shows_minimized_panes, sort_index)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [arrangementId, tabId, "Default", 1, 0, 0]
        )
    }

    private func insertArrangementLayoutPane(_ database: Database, arrangementId: String, paneId: String) throws {
        try database.execute(
            sql: """
                INSERT INTO arrangement_layout_pane(arrangement_id, pane_id, sort_index, ratio)
                VALUES (?, ?, ?, ?)
                """,
            arguments: [arrangementId, paneId, 0, 1.0]
        )
    }

    private func insertDrawer(_ database: Database, drawerId: String, parentPaneId: String) throws {
        try database.execute(
            sql: """
                INSERT INTO drawer(id, parent_pane_id)
                VALUES (?, ?)
                """,
            arguments: [drawerId, parentPaneId]
        )
    }

    private func insertDrawerPane(_ database: Database, drawerId: String, paneId: String) throws {
        try database.execute(
            sql: """
                INSERT INTO drawer_pane(drawer_id, pane_id, sort_index)
                VALUES (?, ?, ?)
                """,
            arguments: [drawerId, paneId, 0]
        )
    }

    private func insertArrangementDrawerView(_ database: Database, arrangementId: String, drawerId: String) throws {
        try database.execute(
            sql: """
                INSERT INTO arrangement_drawer_view(arrangement_id, drawer_id, row_split_ratio)
                VALUES (?, ?, ?)
                """,
            arguments: [arrangementId, drawerId, 0.5]
        )
    }
}

private struct ArrangementFixtureIds {
    let arrangementWorkspaceId = UUID().uuidString
    let foreignPaneWorkspaceId = UUID().uuidString
    let tabId = UUID().uuidString
    let arrangementId = UUID().uuidString
    let foreignPaneId = UUID().uuidString
}

private struct DrawerViewFixtureIds {
    let arrangementWorkspaceId = UUID().uuidString
    let foreignPaneWorkspaceId = UUID().uuidString
    let tabId = UUID().uuidString
    let arrangementId = UUID().uuidString
    let parentPaneId = UUID().uuidString
    let foreignPaneId = UUID().uuidString
    let drawerId = UUID().uuidString
}
