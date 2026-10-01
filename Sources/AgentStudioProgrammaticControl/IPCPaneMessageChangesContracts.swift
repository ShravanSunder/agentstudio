import Foundation

package struct IPCPaneMessageChangesParams: Codable, Equatable, Sendable, IPCSchemaProviding {
    package let handle: String
    package let writer: IPCPaneWriterClaim?
    package let after: UInt64
    package let correlationId: UUID

    package init(handle: String, writer: IPCPaneWriterClaim? = nil, after: UInt64, correlationId: UUID) {
        self.handle = handle
        self.writer = writer
        self.after = after
        self.correlationId = correlationId
    }

    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "handle", description: "handle", schema: .string()),
            .optional("writer", description: "writer", schema: try IPCPaneWriterClaim.ipcSchema()),
            .init(name: "after", description: "after", schema: IPCSchemaScalars.unsignedInteger),
            .init(name: "correlationId", description: "correlationId", schema: IPCSchemaScalars.uuid),
        ])
    }
}

package struct IPCPaneMessageChangesResult: Codable, Equatable, Sendable, IPCSchemaProviding {
    package let entries: [IPCPaneMessageChangeEntry]
    package let nextPosition: UInt64
    package let more: Bool

    package init(entries: [IPCPaneMessageChangeEntry], nextPosition: UInt64, more: Bool) {
        self.entries = entries
        self.nextPosition = nextPosition
        self.more = more
    }

    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(
                name: "entries", description: "entries",
                schema: .array(items: try IPCPaneMessageChangeEntry.ipcSchema())),
            .init(name: "nextPosition", description: "nextPosition", schema: IPCSchemaScalars.unsignedInteger),
            .init(name: "more", description: "more", schema: .boolean),
        ])
    }
}

package struct IPCPaneMessageChangeEntry: Codable, Equatable, Sendable, IPCSchemaProviding {
    package let id: UUID
    package let position: UInt64
    package let messageId: UUID
    package let kind: IPCPaneMessageChangeKind

    package init(id: UUID, position: UInt64, messageId: UUID, kind: IPCPaneMessageChangeKind) {
        self.id = id
        self.position = position
        self.messageId = messageId
        self.kind = kind
    }

    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "id", description: "id", schema: IPCSchemaScalars.uuid),
            .init(name: "position", description: "position", schema: IPCSchemaScalars.unsignedInteger),
            .init(name: "messageId", description: "messageId", schema: IPCSchemaScalars.uuid),
            .init(name: "kind", description: "kind", schema: try IPCPaneMessageChangeKind.ipcSchema()),
        ])
    }
}

package enum IPCPaneMessageChangeKind: Codable, Equatable, Sendable, IPCSchemaProviding {
    case answer(value: IPCPaneAskAnswerValue)
    case dismissal
    case withdrawal

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }
    private enum Kind: String, Codable {
        case answer
        case dismissal
        case withdrawal
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .answer: self = .answer(value: try container.decode(IPCPaneAskAnswerValue.self, forKey: .value))
        case .dismissal: self = .dismissal
        case .withdrawal: self = .withdrawal
        }
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .answer(let value):
            try container.encode(Kind.answer, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .dismissal:
            try container.encode(Kind.dismissal, forKey: .kind)
        case .withdrawal:
            try container.encode(Kind.withdrawal, forKey: .kind)
        }
    }

    package static func ipcSchema() throws -> IPCJSONSchema {
        .oneOf([
            .object(fields: [
                .init(name: "kind", description: "answer", schema: .string(allowedValues: ["answer"])),
                .init(name: "value", description: "value", schema: try IPCPaneAskAnswerValue.ipcSchema()),
            ]),
            .object(fields: [
                .init(name: "kind", description: "dismissal", schema: .string(allowedValues: ["dismissal"]))

            ]),
            .object(fields: [
                .init(name: "kind", description: "withdrawal", schema: .string(allowedValues: ["withdrawal"]))

            ]),
        ])
    }
}
