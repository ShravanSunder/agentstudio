import AgentStudioSessions
import Foundation
import GRDB

/// Cursor and ordering metadata join the effect's existing local.sqlite transaction.
struct CLILifecycleCursorCommitParticipant: SessionsCommitParticipant {
    enum Ordering: Sendable {
        case unchanged
        case unordered(fence: Int64?)
        case ordered
    }
    let storeID: UUID?
    let sequence: Int64?
    let paneID: UUID?
    let ordering: Ordering
    let finalRevokedPaneIDs: @Sendable () -> Set<UUID>

    init(
        storeID: UUID?, sequence: Int64?, paneID: UUID?, ordering: Ordering,
        finalRevokedPaneIDs: @escaping @Sendable () -> Set<UUID> = { [] }
    ) {
        self.storeID = storeID
        self.sequence = sequence
        self.paneID = paneID
        self.ordering = ordering
        self.finalRevokedPaneIDs = finalRevokedPaneIDs
    }

    func commit(in database: Database) throws {
        // Revocation can arrive while qualification or Sessions ingestion is suspended.
        if let paneID, finalRevokedPaneIDs().contains(paneID) { throw CLILifecycleCommitRefusal.retiredPane }
        if let storeID, let sequence {
            try database.execute(
                sql: """
                    INSERT INTO sessions_cli_report_cursor (store_id,last_handled_sequence) VALUES (?,?)
                    ON CONFLICT(store_id) DO UPDATE SET last_handled_sequence =
                        MAX(sessions_cli_report_cursor.last_handled_sequence, excluded.last_handled_sequence)
                    """, arguments: [storeID.uuidString, sequence])
        }
        guard let paneID else { return }
        switch ordering {
        case .unchanged: break
        case .unordered(let fence):
            if let fence { try Self.fenceAwaitingBindings(in: database, through: fence) }
            try database.execute(
                sql: """
                    UPDATE sessions_pane_binding SET evidence_unordered=1, unordered_fence_sequence=?
                    WHERE binding_generation_id=(
                        SELECT binding_generation_id FROM sessions_pane_binding WHERE pane_id=?
                        ORDER BY CASE status WHEN 'active' THEN 0 ELSE 1 END, committed_revision DESC LIMIT 1)
                    """, arguments: [fence, paneID.uuidString])
        case .ordered:
            try database.execute(
                sql: """
                    UPDATE sessions_pane_binding SET evidence_unordered=0, unordered_fence_sequence=NULL
                    WHERE binding_generation_id=(
                        SELECT binding_generation_id FROM sessions_pane_binding WHERE pane_id=?
                        ORDER BY CASE status WHEN 'active' THEN 0 ELSE 1 END, committed_revision DESC LIMIT 1)
                    """, arguments: [paneID.uuidString])
        }
    }

    static func mark(in database: Database, storeID: UUID) throws -> Int64 {
        try Int64.fetchOne(
            database,
            sql: "SELECT last_handled_sequence FROM sessions_cli_report_cursor WHERE store_id=?",
            arguments: [storeID.uuidString]) ?? 0
    }

    /// First successful read fences before any stored envelope can change a pane.
    static func fenceAwaitingBindings(in database: Database, through highWater: Int64) throws {
        try database.execute(
            sql: """
                UPDATE sessions_pane_binding SET unordered_fence_sequence=?
                WHERE evidence_unordered=1 AND unordered_fence_sequence IS NULL
                """, arguments: [highWater])
    }
}

enum CLILifecycleCommitRefusal: Error { case retiredPane }
