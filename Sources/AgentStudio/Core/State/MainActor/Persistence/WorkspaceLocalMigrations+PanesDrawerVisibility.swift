import GRDB

extension WorkspaceLocalMigrations {
    static func registerPanesDrawerVisibilityMigration(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("015_add_panes_drawer_visibility") { database in
            try database.execute(
                sql: """
                    ALTER TABLE local_window_state
                    ADD COLUMN panes_shows_drawers INTEGER NOT NULL DEFAULT 1
                    CHECK (panes_shows_drawers IN (0, 1))
                    """
            )
        }
    }
}
