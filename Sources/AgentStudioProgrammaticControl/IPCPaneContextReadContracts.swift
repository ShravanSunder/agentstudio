import Foundation

package struct IPCPaneLiveMessageCursor: Codable, Equatable, Sendable, IPCSchemaProviding {
    package let rank: Int
    package let position: UInt64

    package init(rank: Int, position: UInt64) {
        self.rank = rank
        self.position = position
    }

    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "rank", description: "rank", schema: IPCSchemaScalars.signedInteger),
            .init(name: "position", description: "position", schema: IPCSchemaScalars.unsignedInteger),
        ])
    }
}

package enum IPCPaneContextReadPage: Codable, Equatable, Sendable, IPCSchemaProviding {
    case first
    case more(source: UUID, after: IPCPaneLiveMessageCursor)

    private enum CodingKeys: String, CodingKey {
        case kind
        case source
        case after
    }
    private enum Kind: String, Codable {
        case first
        case more
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .first: self = .first
        case .more:
            self = .more(
                source: try container.decode(UUID.self, forKey: .source),
                after: try container.decode(IPCPaneLiveMessageCursor.self, forKey: .after))
        }
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .first:
            try container.encode(Kind.first, forKey: .kind)
        case .more(let source, let after):
            try container.encode(Kind.more, forKey: .kind)
            try container.encode(source, forKey: .source)
            try container.encode(after, forKey: .after)
        }
    }

    package static func ipcSchema() throws -> IPCJSONSchema {
        .oneOf([
            .object(fields: [
                .init(name: "kind", description: "first", schema: .string(allowedValues: ["first"]))

            ]),
            .object(fields: [
                .init(name: "kind", description: "more", schema: .string(allowedValues: ["more"])),
                .init(name: "source", description: "source", schema: IPCSchemaScalars.uuid),
                .init(name: "after", description: "after", schema: try IPCPaneLiveMessageCursor.ipcSchema()),
            ]),
        ])
    }
}

package struct IPCPaneContextGetParams: Codable, Equatable, Sendable, IPCSchemaProviding {
    package let handle: String
    package let page: IPCPaneContextReadPage

    package init(handle: String, page: IPCPaneContextReadPage) {
        self.handle = handle
        self.page = page
    }

    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "handle", description: "handle", schema: .string()),
            .init(name: "page", description: "page", schema: try IPCPaneContextReadPage.ipcSchema()),
        ])
    }
}

package struct IPCPaneContextGetResult: Codable, Equatable, Sendable, IPCSchemaProviding {
    package let paneId: UUID
    package let revision: UInt64
    package let agentTitle: String?
    package let agentLine: IPCPaneAgentLineDetail?
    package let session: IPCPaneSessionSummary?
    package let messages: [IPCPaneMessageDetail]
    package let drawerMessages: [IPCPaneDrawerMessageGroup]
    package let links: IPCPaneLinksDetail
    package let pullRequests: IPCPanePullRequestSummaryDetail
    package let truncation: IPCPaneDetailTruncation?

    package init(
        paneId: UUID, revision: UInt64, agentTitle: String? = nil, agentLine: IPCPaneAgentLineDetail? = nil,
        session: IPCPaneSessionSummary? = nil, messages: [IPCPaneMessageDetail],
        drawerMessages: [IPCPaneDrawerMessageGroup], links: IPCPaneLinksDetail,
        pullRequests: IPCPanePullRequestSummaryDetail, truncation: IPCPaneDetailTruncation? = nil
    ) {
        self.paneId = paneId
        self.revision = revision
        self.agentTitle = agentTitle
        self.agentLine = agentLine
        self.session = session
        self.messages = messages
        self.drawerMessages = drawerMessages
        self.links = links
        self.pullRequests = pullRequests
        self.truncation = truncation
    }

    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "paneId", description: "paneId", schema: IPCSchemaScalars.uuid),
            .init(name: "revision", description: "revision", schema: IPCSchemaScalars.unsignedInteger),
            .optional("agentTitle", description: "agentTitle", schema: .string()),
            .optional("agentLine", description: "agentLine", schema: try IPCPaneAgentLineDetail.ipcSchema()),
            .optional("session", description: "session", schema: try IPCPaneSessionSummary.ipcSchema()),
            .init(
                name: "messages", description: "messages", schema: .array(items: try IPCPaneMessageDetail.ipcSchema())),
            .init(
                name: "drawerMessages", description: "drawerMessages",
                schema: .array(items: try IPCPaneDrawerMessageGroup.ipcSchema())),
            .init(name: "links", description: "links", schema: try IPCPaneLinksDetail.ipcSchema()),
            .init(
                name: "pullRequests", description: "pullRequests",
                schema: try IPCPanePullRequestSummaryDetail.ipcSchema()),
            .optional("truncation", description: "truncation", schema: try IPCPaneDetailTruncation.ipcSchema()),
        ])
    }
}

package struct IPCPaneDrawerMessageGroup: Codable, Equatable, Sendable, IPCSchemaProviding {
    package let sourcePaneId: UUID
    package let messages: [IPCPaneMessageDetail]

    package init(sourcePaneId: UUID, messages: [IPCPaneMessageDetail]) {
        self.sourcePaneId = sourcePaneId
        self.messages = messages
    }

    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "sourcePaneId", description: "sourcePaneId", schema: IPCSchemaScalars.uuid),
            .init(
                name: "messages", description: "messages", schema: .array(items: try IPCPaneMessageDetail.ipcSchema())),
        ])
    }
}

package struct IPCPaneDetailTruncation: Codable, Equatable, Sendable, IPCSchemaProviding {
    package let omitted: [IPCPaneOmittedLiveMessages]

    package init(omitted: [IPCPaneOmittedLiveMessages]) {
        self.omitted = omitted
    }

    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(
                name: "omitted", description: "omitted",
                schema: .array(items: try IPCPaneOmittedLiveMessages.ipcSchema()))
        ])
    }
}

package struct IPCPaneOmittedLiveMessages: Codable, Equatable, Sendable, IPCSchemaProviding {
    package let source: UUID
    package let openAsks: Int
    package let unreadNotices: Int
    package let next: IPCPaneLiveMessageCursor

    package init(source: UUID, openAsks: Int, unreadNotices: Int, next: IPCPaneLiveMessageCursor) {
        self.source = source
        self.openAsks = openAsks
        self.unreadNotices = unreadNotices
        self.next = next
    }

    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "source", description: "source", schema: IPCSchemaScalars.uuid),
            .init(name: "openAsks", description: "openAsks", schema: IPCSchemaScalars.signedInteger),
            .init(name: "unreadNotices", description: "unreadNotices", schema: IPCSchemaScalars.signedInteger),
            .init(name: "next", description: "next", schema: try IPCPaneLiveMessageCursor.ipcSchema()),
        ])
    }
}

package enum IPCPaneLinksDetail: String, Codable, CaseIterable, Equatable, Sendable, IPCSchemaProviding {
    case unknown
}
