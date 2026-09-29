import Foundation
import GRDB
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("WorkspacePanesDrawerVisibilityMigrationTests")
struct WorkspacePanesDrawerVisibilityMigrationTests {
    @Test("drawer visibility migration shows drawers for an existing main window")
    func drawerVisibilityMigrationDefaultsExistingWindowToShown() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.bootRequiredMigrator.migrate(
            databaseQueue,
            upTo: "007_add_per_screen_sidebar_organization"
        )
        let windowId = UUIDv7.generate().uuidString
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO local_window_state(
                        window_id, window_role, sidebar_width, filter_text,
                        is_filter_visible, sidebar_collapsed, sidebar_surface, updated_at
                    ) VALUES (?, 'main', 250, '', 0, 0, 'panes', 1)
                    """,
                arguments: [windowId]
            )
        }

        try WorkspaceLocalMigrations.migrateBootRequired(databaseQueue)

        let showsDrawers = try databaseQueue.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT panes_shows_drawers FROM local_window_state WHERE window_id = ?",
                arguments: [windowId]
            )
        }
        #expect(showsDrawers == 1)
    }
}
