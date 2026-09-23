import Foundation
import GRDB

extension WorkspaceLocalMigrations {
    package static let drawerPresentationMigrationIdentifier = "015_create_local_drawer_presentation"

    /// Creates per-owner drawer presentation rows, separate from the cursor
    /// replace-rows set. The legacy global height is imported by a separate
    /// boot data step, never by a conditionally registered migration.
    static func registerDrawerPresentationSchema(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration(drawerPresentationMigrationIdentifier) { database in
            try database.execute(
                sql: """
                    CREATE TABLE local_drawer_presentation (
                        workspace_id TEXT NOT NULL,
                        owner_pane_id TEXT NOT NULL,
                        normal_height_ratio REAL NOT NULL,
                        zoom_side TEXT NOT NULL,
                        updated_at REAL NOT NULL,
                        PRIMARY KEY (workspace_id, owner_pane_id)
                    )
                    """
            )
        }
    }
}
