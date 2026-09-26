import Foundation
import GRDB

/// Core membership reads that bound local drawer presentation rows.
extension WorkspaceCoreRepository {
    /// Pane members of available undo records, so a closed owner keeps its
    /// presentation choices while it can still be restored.
    func fetchAvailableUndoMemberPaneIDs(workspaceID: UUID) throws -> Set<UUID> {
        try databaseWriter.read { database in
            let paneIDs = try String.fetchAll(
                database,
                sql: """
                    SELECT member.pane_id
                    FROM workspace_undo_close_member AS member
                    JOIN workspace_undo_close AS close ON close.close_id = member.close_id
                    WHERE close.workspace_id = ? AND close.state = 'available'
                    """,
                arguments: [workspaceID.uuidString]
            )
            return Set(paneIDs.compactMap(UUID.init(uuidString:)))
        }
    }

    /// Layout panes (never drawer children) of every persisted workspace; the
    /// owners that receive the legacy global drawer height on upgrade.
    func fetchOwningLayoutPaneIDsByWorkspace() throws -> [UUID: Set<UUID>] {
        try databaseWriter.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT pane.id AS pane_id, pane.workspace_id AS workspace_id
                    FROM pane
                    WHERE pane.id NOT IN (SELECT pane_id FROM drawer_pane)
                    """
            )
            return rows.reduce(into: [UUID: Set<UUID>]()) { result, row in
                let storedPaneID: String = row["pane_id"]
                let storedWorkspaceID: String = row["workspace_id"]
                guard let paneID = UUID(uuidString: storedPaneID),
                    let workspaceID = UUID(uuidString: storedWorkspaceID)
                else { return }
                result[workspaceID, default: []].insert(paneID)
            }
        }
    }
}
