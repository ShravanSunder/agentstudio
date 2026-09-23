import Foundation
import GRDB

extension WorkspaceLocalRepository {
    /// Stored `local_drawer_presentation` row. Distinct from the live
    /// `DrawerPresentationPreference`: raw values are validated per field on load.
    struct DrawerPresentationRecord: Equatable, Sendable {
        let ownerPaneId: UUID
        let normalHeightRatio: Double
        let zoomSide: String

        /// Rejects non-finite ratios and unknown side encodings field by field,
        /// falling back to that field's deterministic default.
        var validatedPreference: DrawerPresentationPreference {
            DrawerPresentationPreference(
                normalHeightRatio: DrawerPresentationPreference.validatedNormalHeightRatio(normalHeightRatio)
                    ?? DrawerPresentationPreference.defaultNormalHeightRatio,
                zoomSide: DrawerZoomSide(rawValue: zoomSide) ?? DrawerPresentationPreference.default.zoomSide
            )
        }
    }

    /// One ordinary local save of drawer presentation choices.
    struct DrawerPresentationWrite: Equatable, Sendable {
        let preferencesByOwnerPaneId: [UUID: DrawerPresentationPreference]
        /// Live core panes plus members of available undo records. `nil` when
        /// membership could not be established: rows are merged, none pruned.
        let retainedOwnerPaneIds: Set<UUID>?
    }

    func fetchDrawerPresentationRecords() throws -> [DrawerPresentationRecord] {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.fetchDrawerPresentationRows(database, workspaceId: workspaceId)
        }
    }
}

extension WorkspaceLocalRepositoryStorage {
    static func fetchDrawerPresentationRows(
        _ database: Database,
        workspaceId: UUID
    ) throws -> [WorkspaceLocalRepository.DrawerPresentationRecord] {
        try Row.fetchAll(
            database,
            sql: """
                SELECT owner_pane_id, normal_height_ratio, zoom_side
                FROM local_drawer_presentation
                WHERE workspace_id = ?
                """,
            arguments: [workspaceId.uuidString]
        ).compactMap { row in
            let storedOwnerPaneId: String = row["owner_pane_id"]
            guard let ownerPaneId = UUID(uuidString: storedOwnerPaneId) else { return nil }
            return WorkspaceLocalRepository.DrawerPresentationRecord(
                ownerPaneId: ownerPaneId,
                normalHeightRatio: (row["normal_height_ratio"] as Double?) ?? .nan,
                zoomSide: (row["zoom_side"] as String?) ?? ""
            )
        }
    }

    /// Merges current values and removes only rows outside the retention set,
    /// inside the caller's local transaction.
    static func mergeDrawerPresentationRows(
        _ database: Database,
        workspaceId: UUID,
        write: WorkspaceLocalRepository.DrawerPresentationWrite,
        updatedAt: Date
    ) throws {
        let workspaceIdString = workspaceId.uuidString
        if let retainedOwnerPaneIds = write.retainedOwnerPaneIds {
            let storedOwnerPaneIds = try String.fetchAll(
                database,
                sql: "SELECT owner_pane_id FROM local_drawer_presentation WHERE workspace_id = ?",
                arguments: [workspaceIdString]
            )
            for storedOwnerPaneId in storedOwnerPaneIds
            where !(UUID(uuidString: storedOwnerPaneId).map(retainedOwnerPaneIds.contains) ?? false) {
                try database.execute(
                    sql: "DELETE FROM local_drawer_presentation WHERE workspace_id = ? AND owner_pane_id = ?",
                    arguments: [workspaceIdString, storedOwnerPaneId]
                )
            }
        }
        for (ownerPaneId, preference) in write.preferencesByOwnerPaneId {
            if let retainedOwnerPaneIds = write.retainedOwnerPaneIds, !retainedOwnerPaneIds.contains(ownerPaneId) {
                continue
            }
            try database.execute(
                sql: """
                    INSERT INTO local_drawer_presentation(
                        workspace_id, owner_pane_id, normal_height_ratio, zoom_side, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(workspace_id, owner_pane_id) DO UPDATE SET
                        normal_height_ratio = excluded.normal_height_ratio,
                        zoom_side = excluded.zoom_side,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    workspaceIdString,
                    ownerPaneId.uuidString,
                    preference.normalHeightRatio,
                    preference.zoomSide.rawValue,
                    updatedAt.timeIntervalSince1970,
                ]
            )
        }
    }
}
