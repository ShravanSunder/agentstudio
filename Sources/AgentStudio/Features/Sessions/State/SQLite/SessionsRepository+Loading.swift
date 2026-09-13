import Foundation
import GRDB

extension SessionsRepositoryStorage {
    fileprivate static func loadConversation(
        database: Database,
        providerIdentifier: String,
        providerConversationId: String
    ) throws -> SessionsConversationRecord? {
        try Row.fetchOne(
            database,
            sql: """
                SELECT * FROM sessions_conversation
                WHERE provider_identifier = ? AND provider_conversation_id = ?
                """,
            arguments: [providerIdentifier, providerConversationId]
        ).map { row in
            SessionsConversationRecord(
                id: try decodeUuid(row["id"]),
                providerIdentifier: row["provider_identifier"],
                providerConversationId: row["provider_conversation_id"],
                createdAt: Date(timeIntervalSince1970: row["created_at"]),
                lastReportedAt: Date(timeIntervalSince1970: row["last_reported_at"])
            )
        }
    }

    static func loadContext(
        database: Database,
        query: SessionsRepositoryContextQuery
    ) throws -> SessionsRepositoryContext {
        let revision = try Int64.fetchOne(database, sql: "SELECT MAX(commit_revision) FROM sessions_operation") ?? 0
        switch query {
        case .bind(let paneId, let providerIdentifier, let providerConversationId):
            let bindings = try loadBindings(database: database, paneId: paneId)
            return SessionsRepositoryContext(
                revision: revision,
                matchingConversation: try loadConversation(
                    database: database,
                    providerIdentifier: providerIdentifier,
                    providerConversationId: providerConversationId
                ),
                currentBinding: bindings.first,
                bindings: bindings,
                sources: try loadSources(database: database, paneId: paneId),
                evidence: try loadEvidence(database: database, paneId: paneId),
                messages: [],
                attention: try loadAttention(database: database, paneId: paneId),
                results: try loadResults(database: database, paneId: paneId)
            )
        case .pane(let paneId), .source(let paneId, _):
            let bindings = try loadBindings(database: database, paneId: paneId)
            return SessionsRepositoryContext(
                revision: revision,
                matchingConversation: nil,
                currentBinding: bindings.first,
                bindings: bindings,
                sources: try loadSources(database: database, paneId: paneId),
                evidence: try loadEvidence(database: database, paneId: paneId),
                messages: [],
                attention: try loadAttention(database: database, paneId: paneId),
                results: try loadResults(database: database, paneId: paneId)
            )
        case .message(let occurrenceId):
            return SessionsRepositoryContext(
                revision: revision,
                matchingConversation: nil,
                currentBinding: nil,
                bindings: [],
                sources: [],
                evidence: [],
                messages: try loadMessage(database: database, occurrenceId: occurrenceId).map { [$0] } ?? [],
                attention: [],
                results: []
            )
        case .allActiveSources:
            let bindings = try loadActiveBindings(database: database)
            return SessionsRepositoryContext(
                revision: revision,
                matchingConversation: nil,
                currentBinding: nil,
                bindings: bindings,
                sources: try loadActiveSources(database: database),
                evidence: [],
                messages: [],
                attention: try loadActiveAttention(database: database),
                results: []
            )
        }
    }

    static func loadSnapshot(database: Database, query: SessionsSnapshotQuery) throws -> SessionsSnapshot {
        switch query {
        case .unattributed(let page):
            let revision =
                try Int64.fetchOne(
                    database,
                    sql: "SELECT MAX(commit_revision) FROM sessions_operation"
                ) ?? 0
            let messagePage = try loadMessagePage(
                database: database,
                paneId: nil,
                unattributedOnly: true,
                page: page,
                snapshotRevision: revision
            )
            return SessionsSnapshot(
                revision: revision,
                currentBinding: nil,
                state: .unknown,
                stateOrigin: nil,
                messages: messagePage.messages,
                currentAttention: [],
                staleAttention: [],
                results: [],
                historicalOccurrenceIds: [],
                losses: [],
                nextCursor: messagePage.nextCursor
            )
        case .pane(let paneId, let page):
            let context = try loadContext(database: database, query: .pane(paneId))
            let messagePage = try loadMessagePage(
                database: database,
                paneId: paneId,
                unattributedOnly: false,
                page: page,
                snapshotRevision: context.revision
            )
            guard let binding = context.currentBinding else {
                return SessionsSnapshot(
                    revision: context.revision,
                    currentBinding: nil,
                    state: .unknown,
                    stateOrigin: nil,
                    messages: messagePage.messages,
                    currentAttention: [],
                    staleAttention: [],
                    results: context.results,
                    historicalOccurrenceIds: context.evidence.filter { $0.freshness != .live }.map(\.occurrenceId),
                    losses: try loadLosses(database: database, paneId: paneId),
                    nextCursor: messagePage.nextCursor
                )
            }
            let endedSources = Set(context.sources.filter { $0.status != .active }.map(\.sourceGenerationId))
            let activeSources = Set(context.sources.filter { $0.status == .active }.map(\.sourceGenerationId))
            let currentTurnId = SessionsEvidenceReducer.currentTurnId(
                evidence: context.evidence,
                bindingGenerationId: binding.bindingGenerationId,
                activeSourceGenerationIds: activeSources
            )
            let projection = SessionsEvidenceReducer.reduce(
                SessionsReductionInput(
                    conversationId: binding.conversationId,
                    bindingGenerationId: binding.bindingGenerationId,
                    currentTurnId: currentTurnId,
                    evidence: context.evidence,
                    endedSourceGenerationIds: endedSources
                )
            )
            return SessionsSnapshot(
                revision: context.revision,
                currentBinding: binding,
                state: projection.state,
                stateOrigin: projection.stateOrigin,
                messages: messagePage.messages,
                currentAttention: projection.currentAttention,
                staleAttention: projection.staleAttention,
                results: context.results,
                historicalOccurrenceIds: projection.historicalOccurrenceIds,
                losses: try loadLosses(database: database, paneId: paneId),
                nextCursor: messagePage.nextCursor
            )
        }
    }
}

extension SessionsRepositoryStorage {
    fileprivate static func loadBindings(database: Database, paneId: UUID) throws -> [SessionsBindingRecord] {
        try Row.fetchAll(
            database,
            sql: """
                SELECT binding.*, conversation.provider_identifier, conversation.provider_conversation_id
                FROM sessions_pane_binding AS binding
                JOIN sessions_conversation AS conversation ON conversation.id = binding.conversation_id
                WHERE binding.pane_id = ?
                ORDER BY CASE binding.status WHEN 'active' THEN 0 ELSE 1 END,
                         binding.started_at DESC,
                         binding.binding_generation_id ASC
                """,
            arguments: [paneId.uuidString]
        ).map(decodeBinding)
    }

    fileprivate static func loadActiveBindings(database: Database) throws -> [SessionsBindingRecord] {
        try Row.fetchAll(
            database,
            sql: """
                SELECT binding.*, conversation.provider_identifier, conversation.provider_conversation_id
                FROM sessions_pane_binding AS binding
                JOIN sessions_conversation AS conversation ON conversation.id = binding.conversation_id
                WHERE binding.status = 'active'
                ORDER BY binding.pane_id, binding.started_at
                """
        ).map(decodeBinding)
    }

    fileprivate static func loadSources(database: Database, paneId: UUID) throws -> [SessionsSourceRecord] {
        try Row.fetchAll(
            database,
            sql: """
                SELECT source.*
                FROM sessions_source AS source
                JOIN sessions_pane_binding AS binding
                  ON binding.binding_generation_id = source.binding_generation_id
                WHERE binding.pane_id = ?
                ORDER BY source.started_at, source.id
                """,
            arguments: [paneId.uuidString]
        ).map(decodeSource)
    }

    fileprivate static func loadActiveSources(database: Database) throws -> [SessionsSourceRecord] {
        try Row.fetchAll(
            database,
            sql: "SELECT * FROM sessions_source WHERE status = 'active' ORDER BY started_at, id"
        ).map(decodeSource)
    }

    fileprivate static func loadEvidence(database: Database, paneId: UUID) throws -> [SessionsEvidenceRecord] {
        try Row.fetchAll(
            database,
            sql: """
                SELECT evidence.*,
                       attention.request_id AS evidence_request_id,
                       attention.explanation_text AS evidence_explanation_text
                FROM sessions_evidence AS evidence
                JOIN sessions_pane_binding AS binding
                  ON binding.binding_generation_id = evidence.binding_generation_id
                LEFT JOIN sessions_attention AS attention ON attention.id = evidence.attention_id
                WHERE binding.pane_id = ?
                ORDER BY evidence.occurred_at, evidence.occurrence_id
                """,
            arguments: [paneId.uuidString]
        ).map(decodeEvidence)
    }

    fileprivate struct LoadedMessagePage {
        let messages: [SessionsMessageRecord]
        let nextCursor: SessionsSnapshotCursor?
    }

    fileprivate static func loadMessagePage(
        database: Database,
        paneId: UUID?,
        unattributedOnly: Bool,
        page: SessionsSnapshotPage,
        snapshotRevision: Int64
    ) throws -> LoadedMessagePage {
        guard page.limit > 0 else { throw SessionsRepositoryError.invalidPageLimit(page.limit) }
        var conditions: [String] = []
        var arguments: [any DatabaseValueConvertible] = []
        if unattributedOnly {
            conditions.append("attribution = 'unattributed'")
        } else if let paneId {
            conditions.append("pane_id = ?")
            arguments.append(paneId.uuidString)
        } else {
            return LoadedMessagePage(messages: [], nextCursor: nil)
        }
        if let after = page.after {
            guard after.snapshotRevision == snapshotRevision else {
                throw SessionsRepositoryError.staleSnapshotCursor(
                    expectedRevision: after.snapshotRevision,
                    actualRevision: snapshotRevision
                )
            }
            conditions.append(
                "(committed_revision > ? OR (committed_revision = ? AND occurrence_id > ?))"
            )
            arguments.append(after.commitRevision)
            arguments.append(after.commitRevision)
            arguments.append(after.occurrenceId.uuidString)
        }
        arguments.append(page.limit + 1)
        let rows = try Row.fetchAll(
            database,
            sql: """
                SELECT * FROM sessions_message
                WHERE \(conditions.joined(separator: " AND "))
                ORDER BY committed_revision, occurrence_id
                LIMIT ?
                """,
            arguments: StatementArguments(arguments)
        )
        let retainedRows = Array(rows.prefix(page.limit))
        let nextCursor: SessionsSnapshotCursor?
        if rows.count > page.limit, let lastRow = retainedRows.last {
            nextCursor = SessionsSnapshotCursor(
                snapshotRevision: snapshotRevision,
                commitRevision: lastRow["committed_revision"],
                occurrenceId: try decodeUuid(lastRow["occurrence_id"])
            )
        } else {
            nextCursor = nil
        }
        return LoadedMessagePage(
            messages: try retainedRows.map(decodeMessage),
            nextCursor: nextCursor
        )
    }

    fileprivate static func loadMessage(database: Database, occurrenceId: UUID) throws -> SessionsMessageRecord? {
        try Row.fetchOne(
            database,
            sql: "SELECT * FROM sessions_message WHERE occurrence_id = ?",
            arguments: [occurrenceId.uuidString]
        ).map(decodeMessage)
    }

    fileprivate static func loadAttention(database: Database, paneId: UUID) throws -> [SessionsStoredAttentionRecord] {
        try Row.fetchAll(
            database,
            sql: """
                SELECT attention.*
                FROM sessions_attention AS attention
                JOIN sessions_pane_binding AS binding
                  ON binding.binding_generation_id = attention.binding_generation_id
                WHERE binding.pane_id = ?
                ORDER BY attention.opened_at, attention.id
                """,
            arguments: [paneId.uuidString]
        ).map(decodeAttention)
    }

    fileprivate static func loadActiveAttention(database: Database) throws -> [SessionsStoredAttentionRecord] {
        try Row.fetchAll(
            database,
            sql: "SELECT * FROM sessions_attention WHERE disposition = 'current' ORDER BY opened_at, id"
        ).map(decodeAttention)
    }

    fileprivate static func loadResults(database: Database, paneId: UUID) throws -> [SessionsResultRecord] {
        try Row.fetchAll(
            database,
            sql: """
                SELECT result.*
                FROM sessions_result AS result
                JOIN sessions_pane_binding AS binding
                  ON binding.binding_generation_id = result.binding_generation_id
                WHERE binding.pane_id = ?
                ORDER BY result.updated_at, result.id
                """,
            arguments: [paneId.uuidString]
        ).map(decodeResult)
    }

    fileprivate static func loadLosses(database: Database, paneId: UUID) throws -> [SessionsLossRecord] {
        try Row.fetchAll(
            database,
            sql: "SELECT * FROM sessions_loss WHERE pane_id = ? ORDER BY occurred_at, id",
            arguments: [paneId.uuidString]
        ).map { row in
            SessionsLossRecord(
                id: try decodeUuid(row["id"]),
                paneId: try decodeUuid(row["pane_id"]),
                conversationId: try decodeOptionalUuid(row["conversation_id"]),
                bindingGenerationId: try decodeOptionalUuid(row["binding_generation_id"]),
                sourceGenerationId: try decodeOptionalUuid(row["source_generation_id"]),
                providerIdentifier: row["provider_identifier"],
                eventKind: row["event_kind"],
                reason: try decodeEnum(row["reason_code"], as: SessionsLossReason.self),
                occurredAt: Date(timeIntervalSince1970: row["occurred_at"])
            )
        }
    }

}
