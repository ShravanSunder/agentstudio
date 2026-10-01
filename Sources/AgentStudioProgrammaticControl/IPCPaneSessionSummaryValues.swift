import Foundation

package enum IPCPaneSessionWorkingState: String, Codable, CaseIterable, Equatable, Sendable, IPCSchemaProviding {
    case active
    case monitoring
}

package enum IPCPaneSessionIdleState: String, Codable, CaseIterable, Equatable, Sendable, IPCSchemaProviding {
    case done
    case ready
    case interrupted
    case ended
}

package enum IPCPaneSessionStatus: Codable, Equatable, Sendable, IPCSchemaProviding {
    case needsYou(reason: IPCPaneAskReason)
    case failed(category: String)
    case working(state: IPCPaneSessionWorkingState)
    case idle(state: IPCPaneSessionIdleState)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case kind
        case reason
        case category
        case state
    }
    private enum Kind: String, Codable {
        case needsYou
        case failed
        case working
        case idle
        case unknown
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .needsYou: self = .needsYou(reason: try container.decode(IPCPaneAskReason.self, forKey: .reason))
        case .failed: self = .failed(category: try container.decode(String.self, forKey: .category))
        case .working: self = .working(state: try container.decode(IPCPaneSessionWorkingState.self, forKey: .state))
        case .idle: self = .idle(state: try container.decode(IPCPaneSessionIdleState.self, forKey: .state))
        case .unknown: self = .unknown
        }
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .needsYou(let reason):
            try container.encode(Kind.needsYou, forKey: .kind)
            try container.encode(reason, forKey: .reason)
        case .failed(let category):
            try container.encode(Kind.failed, forKey: .kind)
            try container.encode(category, forKey: .category)
        case .working(let state):
            try container.encode(Kind.working, forKey: .kind)
            try container.encode(state, forKey: .state)
        case .idle(let state):
            try container.encode(Kind.idle, forKey: .kind)
            try container.encode(state, forKey: .state)
        case .unknown:
            try container.encode(Kind.unknown, forKey: .kind)
        }
    }

    package static func ipcSchema() throws -> IPCJSONSchema {
        .oneOf([
            .object(fields: [
                .init(name: "kind", description: "needsYou", schema: .string(allowedValues: ["needsYou"])),
                .init(name: "reason", description: "reason", schema: try IPCPaneAskReason.ipcSchema()),
            ]),
            .object(fields: [
                .init(name: "kind", description: "failed", schema: .string(allowedValues: ["failed"])),
                .init(name: "category", description: "category", schema: .string()),
            ]),
            .object(fields: [
                .init(name: "kind", description: "working", schema: .string(allowedValues: ["working"])),
                .init(name: "state", description: "state", schema: try IPCPaneSessionWorkingState.ipcSchema()),
            ]),
            .object(fields: [
                .init(name: "kind", description: "idle", schema: .string(allowedValues: ["idle"])),
                .init(name: "state", description: "state", schema: try IPCPaneSessionIdleState.ipcSchema()),
            ]),
            .object(fields: [
                .init(name: "kind", description: "unknown", schema: .string(allowedValues: ["unknown"]))

            ]),
        ])
    }
}

package struct IPCPaneSessionSummary: Codable, Equatable, Sendable, IPCSchemaProviding {
    package let id: UUID
    package let provider: String
    package let conversationId: String
    package let bindingGeneration: UUID
    package let status: IPCPaneSessionStatus
    package let providerPrompts: [IPCPaneProviderPromptSummary]

    package init(
        id: UUID, provider: String, conversationId: String, bindingGeneration: UUID, status: IPCPaneSessionStatus,
        providerPrompts: [IPCPaneProviderPromptSummary]
    ) {
        self.id = id
        self.provider = provider
        self.conversationId = conversationId
        self.bindingGeneration = bindingGeneration
        self.status = status
        self.providerPrompts = providerPrompts
    }

    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "id", description: "id", schema: IPCSchemaScalars.uuid),
            .init(name: "provider", description: "provider", schema: .string()),
            .init(name: "conversationId", description: "conversationId", schema: .string()),
            .init(name: "bindingGeneration", description: "bindingGeneration", schema: IPCSchemaScalars.uuid),
            .init(name: "status", description: "status", schema: try IPCPaneSessionStatus.ipcSchema()),
            .init(
                name: "providerPrompts", description: "providerPrompts",
                schema: .array(items: try IPCPaneProviderPromptSummary.ipcSchema())),
        ])
    }
}

package struct IPCPaneProviderPromptSummary: Codable, Equatable, Sendable, IPCSchemaProviding {
    package let reason: IPCPaneAskReason
    package let observedAt: Date
    package let summary: String?

    package init(reason: IPCPaneAskReason, observedAt: Date, summary: String? = nil) {
        self.reason = reason
        self.observedAt = observedAt
        self.summary = summary
    }

    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "reason", description: "reason", schema: try IPCPaneAskReason.ipcSchema()),
            .init(name: "observedAt", description: "observedAt", schema: .number()),
            .optional("summary", description: "summary", schema: .string()),
        ])
    }
}
