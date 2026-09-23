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

/// Outcome of capturing the legacy import inputs before local migration.
package enum LegacyDrawerPresentationImportCapture: Equatable, Sendable {
    /// No finite legacy height exists; nothing to import or clear.
    case noLegacyValue
    case captured(LegacyDrawerPresentationImport)
    /// Owning panes could not be read. The import stays pending and the
    /// legacy key is kept for a later boot; the schema still migrates.
    case ownerEnumerationFailed

    package static func capture(
        source: LegacyDrawerPresentationSource?,
        enumerateOwners: () throws -> [UUID: Set<UUID>]
    ) -> Self {
        guard let legacyHeightRatio = source?.readHeightRatio(),
            DrawerPresentationPreference.validatedNormalHeightRatio(legacyHeightRatio) != nil
        else { return .noLegacyValue }
        guard let owningPaneIdsByWorkspaceId = try? enumerateOwners() else { return .ownerEnumerationFailed }
        guard
            let legacyImport = LegacyDrawerPresentationImport(
                legacyHeightRatio: legacyHeightRatio,
                owningPaneIdsByWorkspaceId: owningPaneIdsByWorkspaceId
            )
        else { return .noLegacyValue }
        return .captured(legacyImport)
    }

    package var importToApply: LegacyDrawerPresentationImport? {
        guard case .captured(let legacyImport) = self else { return nil }
        return legacyImport
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
    package static let legacyDrawerHeightImportMigrationIdentifier = "016_import_legacy_drawer_height"

    package static func migrateBootRequired(
        _ writer: any DatabaseWriter,
        legacyDrawerPresentationImport: LegacyDrawerPresentationImport? = nil
    ) throws {
        try bootRequiredMigrator(legacyDrawerPresentationImport: legacyDrawerPresentationImport).migrate(writer)
    }

    static func registerDrawerPresentationMigrations(
        in migrator: inout DatabaseMigrator,
        legacyImport: LegacyDrawerPresentationImport?
    ) {
        registerDrawerPresentationSchema(in: &migrator)
        if let legacyImport {
            registerLegacyDrawerHeightImport(in: &migrator, legacyImport: legacyImport)
        }
    }

    /// Creates per-owner drawer presentation rows, separate from the cursor
    /// replace-rows set.
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

    /// Registered only when the legacy height and every persisted owning pane
    /// were captured, so the schema version records the import only after its
    /// rows commit. Rows already written by a later save are kept.
    static func registerLegacyDrawerHeightImport(
        in migrator: inout DatabaseMigrator,
        legacyImport: LegacyDrawerPresentationImport
    ) {
        migrator.registerMigration(legacyDrawerHeightImportMigrationIdentifier) { database in
            let importedAt = Date().timeIntervalSince1970
            for (workspaceId, owningPaneIds) in legacyImport.owningPaneIdsByWorkspaceId {
                for ownerPaneId in owningPaneIds {
                    try database.execute(
                        sql: """
                            INSERT OR IGNORE INTO local_drawer_presentation(
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
