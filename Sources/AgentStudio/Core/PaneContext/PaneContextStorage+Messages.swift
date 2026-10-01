import AgentStudioInfrastructure
import Foundation
import GRDB

extension PaneContextStorage {
    static func message(_ database: Database, paneId: PaneId, messageId: AgentMessageId) throws
        -> PaneContextStoredMessage?
    {
        if let row = try Row.fetchOne(
            database, sql: "SELECT * FROM pane_request WHERE pane_id = ? AND message_id = ?",
            arguments: [paneId.uuidString, messageId.uuid.uuidString])
        {
            return try requestMessage(row, database: database)
        }
        if let row = try Row.fetchOne(
            database, sql: "SELECT * FROM pane_event WHERE pane_id = ? AND message_id = ? AND kind = 'notice'",
            arguments: [paneId.uuidString, messageId.uuid.uuidString])
        {
            return try noticeMessage(row, database: database)
        }
        return nil
    }

    static func messages(_ database: Database, paneId: PaneId) throws -> [PaneContextStoredMessage] {
        let requests = try Row.fetchAll(
            database, sql: "SELECT * FROM pane_request WHERE pane_id = ? AND display_hidden = 0",
            arguments: [paneId.uuidString]
        ).map { try requestMessage($0, database: database) }
        let notices = try Row.fetchAll(
            database, sql: "SELECT * FROM pane_event WHERE pane_id = ? AND kind = 'notice' AND display_hidden = 0",
            arguments: [paneId.uuidString]
        ).map { try noticeMessage($0, database: database) }
        return requests + notices
    }

    static func requestMessage(_ row: Row, database: Database) throws -> PaneContextStoredMessage {
        let rowId = try uuid(row, "id")
        let waitingKind: String = try required(row, "waiting")
        let waiting: AskWaiting
        switch waitingKind {
        case "nonBlocking": waiting = .nonBlocking
        case "blocking": waiting = .blocking(deadline: try date(row, "deadline"))
        default: throw PaneContextStorageFailure.decode("waiting")
        }
        return PaneContextStoredMessage(
            rowId: rowId, position: try unsigned(row, "position"),
            detail: AgentMessageDetail(
                id: AgentMessageId(existingUUID: try uuid(row, "message_id")),
                sourcePaneId: PaneId(existingUUID: try uuid(row, "pane_id")), sender: try sender(row, prefix: "sender"),
                sentAt: try date(row, "sent_at"), sourceOccurredAt: try optionalDate(row, "source_occurred_at"),
                importance: try importance(row), body: try required(row, "body"), why: try optional(row, "why"),
                actions: try loadActions(database, table: "pane_request_action", parentId: rowId),
                shape: .ask(
                    try reason(row), try form(row, database: database), waiting, try askState(row, database: database))
            ),
            settledAt: try optionalDate(row, "settled_at"), displayHidden: try flag(row, "display_hidden")
        )
    }

    static func noticeMessage(_ row: Row, database: Database) throws -> PaneContextStoredMessage {
        let rowId = try uuid(row, "id")
        let stateName: String = try required(row, "notice_state")
        let state: NoticeState
        switch stateName {
        case "unread": state = .unread
        case "read": state = .read
        case "dismissed": state = .dismissed
        case "withdrawn": state = .withdrawn
        default: throw PaneContextStorageFailure.decode("notice_state")
        }
        return PaneContextStoredMessage(
            rowId: rowId, position: try unsigned(row, "position"),
            detail: AgentMessageDetail(
                id: AgentMessageId(existingUUID: try uuid(row, "message_id")),
                sourcePaneId: PaneId(existingUUID: try uuid(row, "pane_id")), sender: try sender(row, prefix: "sender"),
                sentAt: try date(row, "sent_at"), sourceOccurredAt: try optionalDate(row, "source_occurred_at"),
                importance: try importance(row), body: try required(row, "body"), why: try optional(row, "why"),
                actions: try loadActions(database, table: "pane_event_action", parentId: rowId), shape: .notice(state)
            ),
            settledAt: try optionalDate(row, "settled_at"), displayHidden: try flag(row, "display_hidden")
        )
    }

    static func recordMessage(_ request: PaneMessageSendRequest, database: Database, now: Date) throws {
        let rowId = UUIDv7.generate()
        let position = try nextPosition(database, paneId: request.paneId)
        let source = request.sourceOccurredAt.flatMap {
            $0.timeIntervalSince(now) <= AppPolicies.PaneContext.maximumSourceFutureSkew ? $0 : nil
        }
        var fields = senderFields(request.sender, prefix: "sender")
        fields.merge(
            [
                "id": sqlValue(rowId.uuidString), "pane_id": sqlValue(request.paneId.uuidString),
                "message_id": sqlValue(request.messageId.uuid.uuidString),
                "position": sqlValue(try integer(position, field: "position")),
                "importance": sqlValue(importanceName(request.importance)), "body": sqlValue(request.body),
                "why": sqlValue(request.why),
                "sent_at": sqlValue(try timestamp(now)), "source_occurred_at": sqlValue(try source.map(timestamp)),
                "intent_source_occurred_at": sqlValue(try request.sourceOccurredAt.map(timestamp)),
            ], uniquingKeysWith: { _, new in new })
        switch request.shape {
        case .notice:
            fields["kind"] = sqlValue("notice")
            fields["subject_id"] = sqlValue(request.messageId.uuid.uuidString)
            fields["notice_state"] = sqlValue("unread")
            try insert(database, table: "pane_event", fields: fields)
            try saveActions(request.actions, database: database, table: "pane_event_action", parentId: rowId)
        case .ask(let reason, let form, let waiting):
            fields["reason"] = sqlValue(reasonName(reason))
            fields["state"] = sqlValue("open")
            fields.merge(formFields(form), uniquingKeysWith: { _, new in new })
            switch waiting {
            case .nonBlocking: fields["waiting"] = sqlValue("nonBlocking")
            case .blocking(let deadline):
                fields["waiting"] = sqlValue("blocking")
                fields["deadline"] = sqlValue(try timestamp(deadline))
            }
            try insert(database, table: "pane_request", fields: fields)
            try saveForm(form, database: database, requestId: rowId)
            try saveActions(request.actions, database: database, table: "pane_request_action", parentId: rowId)
        }
        try bumpRevision(database, paneId: request.paneId)
    }

    static func sameIntent(_ request: PaneMessageSendRequest, stored: PaneContextStoredMessage, database: Database)
        throws -> Bool
    {
        let detail = stored.detail
        guard writerKey(detail.sender) == writerKey(request.sender), detail.importance == request.importance,
            detail.body == request.body, detail.why == request.why, detail.actions == request.actions
        else { return false }
        let table: String
        switch detail.shape {
        case .notice: table = "pane_event"
        case .ask: table = "pane_request"
        }
        guard
            let row = try Row.fetchOne(
                database, sql: "SELECT intent_source_occurred_at FROM \(table) WHERE id = ?",
                arguments: [stored.rowId.uuidString])
        else { return false }
        let storedSource: Int64? = try optional(row, "intent_source_occurred_at")
        guard storedSource == (try request.sourceOccurredAt.map(timestamp)) else { return false }
        switch (request.shape, detail.shape) {
        case (.notice, .notice): return true
        case (
            .ask(let reason, let form, let waiting), .ask(let existingReason, let existingForm, let existingWaiting, _)
        ):
            return reason == existingReason && form == existingForm && waiting == existingWaiting
        default: return false
        }
    }

    static func appendChange(_ database: Database, message: PaneContextStoredMessage, kind: String, now: Date) throws
        -> UInt64
    {
        let position = try nextPosition(database, paneId: message.detail.sourcePaneId)
        var fields = senderFields(message.detail.sender, prefix: "sender")
        fields.merge(
            [
                "id": sqlValue(UUIDv7.generate().uuidString), "kind": sqlValue(kind),
                "pane_id": sqlValue(message.detail.sourcePaneId.uuidString),
                "position": sqlValue(try integer(position, field: "position")),
                "subject_id": sqlValue(message.detail.id.uuid.uuidString), "sent_at": sqlValue(try timestamp(now)),
            ], uniquingKeysWith: { _, new in new })
        try insert(database, table: "pane_event", fields: fields)
        return position
    }
}
