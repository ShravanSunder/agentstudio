import AgentStudioSessions
import Foundation
import GRDB

/// Cursor and ordering metadata join the effect's existing local.sqlite transaction.
struct CLILifecycleCursorCommitParticipant: SessionsCommitParticipant {
    enum Ordering: Sendable {
        case unordered(fence: Int64?)
        case refused(fence: Int64?)
        case ordered(providerIdentifier: String, conversationID: String, correlationID: UUID)
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
        switch ordering {
        case .unordered(let fence):
            guard let paneID else { return }
            if let fence { try Self.fenceAwaitingBindings(in: database, through: fence) }
            try database.execute(
                sql: """
                    UPDATE sessions_pane_binding SET evidence_unordered=1, unordered_fence_sequence=?
                    WHERE binding_generation_id=(\(Self.latestBindingSQL))
                    """, arguments: [fence, paneID.uuidString])
        case .refused(let fence):
            // Unknown order keeps an awaiting fence; sequenced refusals never
            // lower an existing fence or clear uncertainty established earlier.
            let target =
                paneID == nil ? "provider_ended_at IS NULL" : "binding_generation_id=(\(Self.latestBindingSQL))"
            var arguments: StatementArguments = [fence, fence]
            if let paneID { arguments += [paneID.uuidString] }
            try database.execute(
                sql: """
                    UPDATE sessions_pane_binding SET unordered_fence_sequence=
                        CASE WHEN ? IS NULL OR (evidence_unordered=1 AND unordered_fence_sequence IS NULL)
                             THEN NULL ELSE MAX(COALESCE(unordered_fence_sequence,0),?) END,
                        evidence_unordered=1
                    WHERE \(target)
                    """, arguments: arguments)
        case .ordered(let providerIdentifier, let conversationID, let correlationID):
            guard let paneID else { return }
            // The Sessions effect has already run in this transaction. A new
            // start can clear its new generation; a late old end cannot clear
            // the pane's latest established generation, even when a conversation
            // UUID was rebound: use the committed effect's own generation too.
            try database.execute(
                sql: """
                    UPDATE sessions_pane_binding SET evidence_unordered=0, unordered_fence_sequence=NULL
                    WHERE binding_generation_id=(\(Self.latestBindingSQL))
                      AND conversation_id IN (
                        SELECT id FROM sessions_conversation
                        WHERE provider_identifier=? AND provider_conversation_id=?)
                      AND binding_generation_id IN (
                        SELECT COALESCE(effect.binding_generation_id, source.binding_generation_id)
                        FROM sessions_operation AS effect
                        LEFT JOIN sessions_source AS source
                          ON effect.outcome_kind='sourceEnded'
                         AND source.source_generation_id=effect.outcome_entity_id
                        WHERE effect.operation_scope=? AND effect.correlation_id=?)
                      AND (evidence_unordered=0 OR unordered_fence_sequence < ?)
                    """,
                arguments: [
                    paneID.uuidString, providerIdentifier, conversationID,
                    "pane:\(paneID.uuidString)", correlationID.uuidString, sequence,
                ])
        }
    }

    private static let latestBindingSQL = """
        SELECT binding.binding_generation_id FROM sessions_pane_binding AS binding
        JOIN sessions_operation AS establishment
          ON establishment.binding_generation_id=binding.binding_generation_id
         AND establishment.outcome_kind IN ('bindingEstablished','bindingReplaced')
        WHERE binding.pane_id=?
        GROUP BY binding.binding_generation_id
        ORDER BY MIN(establishment.commit_revision) DESC LIMIT 1
        """

    /// Only the existing local writer adopts history, together with its loss fence.
    static func reconcileStore(in database: Database, presentStoreID: UUID?) throws {
        let established = try String.fetchAll(database, sql: "SELECT store_id FROM sessions_cli_report_cursor")
        guard !established.isEmpty, established.contains(where: { $0 != presentStoreID?.uuidString }) else { return }
        try database.execute(
            sql: """
                UPDATE sessions_pane_binding SET evidence_unordered=1, unordered_fence_sequence=NULL
                WHERE provider_ended_at IS NULL
                """)
        try database.execute(sql: "DELETE FROM sessions_cli_report_cursor")
        if let presentStoreID {
            try database.execute(
                sql: "INSERT INTO sessions_cli_report_cursor (store_id,last_handled_sequence) VALUES (?,0)",
                arguments: [presentStoreID.uuidString])
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
