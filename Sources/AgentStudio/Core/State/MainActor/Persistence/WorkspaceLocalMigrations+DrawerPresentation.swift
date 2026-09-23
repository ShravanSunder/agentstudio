import Foundation
import GRDB

/// Inputs captured before the local migration transaction for the one-time
/// cutover from the retired global drawer height to per-owner preferences.
package struct LegacyDrawerPresentationImport: Equatable, Sendable {
    /// Finite legacy ratio, already clamped into the saved range.
    let normalHeightRatio: Double
    /// Owning layout panes of every persisted workspace at upgrade time.
    let owningPaneIdsByWorkspaceId: [UUID: Set<UUID>]

    package init?(legacyHeightRatio: Double?, owningPaneIdsByWorkspaceId: [UUID: Set<UUID>]) {
        guard let legacyHeightRatio,
            let normalHeightRatio = DrawerPresentationPreference.validatedNormalHeightRatio(legacyHeightRatio)
        else { return nil }
        self.normalHeightRatio = normalHeightRatio
        self.owningPaneIdsByWorkspaceId = owningPaneIdsByWorkspaceId
    }
}

/// Where the retired global drawer height is read from and cleared after the
/// import commits. Production uses the app's standard defaults; tests inject
/// their own value so they never touch a developer's defaults domain.
package struct LegacyDrawerPresentationSource: Sendable {
    package static let legacyHeightRatioKey = "drawerHeightRatio"

    let readHeightRatio: @Sendable () -> Double?
    let clear: @Sendable () -> Void

    package init(
        readHeightRatio: @escaping @Sendable () -> Double?,
        clear: @escaping @Sendable () -> Void
    ) {
        self.readHeightRatio = readHeightRatio
        self.clear = clear
    }

    package static let standardUserDefaults = Self(
        readHeightRatio: {
            UserDefaults.standard.object(forKey: legacyHeightRatioKey) as? Double
        },
        clear: {
            UserDefaults.standard.removeObject(forKey: legacyHeightRatioKey)
        }
    )
}

extension WorkspaceLocalMigrations {
    package static let drawerPresentationMigrationIdentifier = "015_create_local_drawer_presentation"

    package static func migrateBootRequired(
        _ writer: any DatabaseWriter,
        legacyDrawerPresentationImport: LegacyDrawerPresentationImport? = nil
    ) throws {
        try bootRequiredMigrator(legacyDrawerPresentationImport: legacyDrawerPresentationImport).migrate(writer)
    }

    /// Creates per-owner drawer presentation rows, separate from the cursor
    /// replace-rows set. The legacy import runs inside this migration so the
    /// schema version records completion only after the imported rows commit.
    static func registerDrawerPresentationSchema(
        in migrator: inout DatabaseMigrator,
        legacyImport: LegacyDrawerPresentationImport?
    ) {
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
            guard let legacyImport else { return }
            let importedAt = Date().timeIntervalSince1970
            for (workspaceId, owningPaneIds) in legacyImport.owningPaneIdsByWorkspaceId {
                for ownerPaneId in owningPaneIds {
                    try database.execute(
                        sql: """
                            INSERT INTO local_drawer_presentation(
                                workspace_id, owner_pane_id, normal_height_ratio, zoom_side, updated_at
                            )
                            VALUES (?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            workspaceId.uuidString,
                            ownerPaneId.uuidString,
                            legacyImport.normalHeightRatio,
                            DrawerZoomSide.terminal.rawValue,
                            importedAt,
                        ]
                    )
                }
            }
        }
    }
}
