import Foundation

typealias WorktreeAnnotationBatchSnapshotV1 = WorktreeAnnotationBatchSnapshot

enum WorktreeAnnotationBatchFormatVersion {
    static let current = WorktreeAnnotationBatchSnapshotV2.currentFormatVersion
    static let supported = Set([
        WorktreeAnnotationBatchSnapshotV1.currentFormatVersion,
        WorktreeAnnotationBatchSnapshotV2.currentFormatVersion,
    ])
}

struct WorktreeAnnotationBatchSnapshotV2: Codable, Equatable, Sendable {
    static let currentFormatVersion = 2
    static let schema = WorktreeAnnotationBatchSnapshotV1.schema

    typealias SessionContext = WorktreeAnnotationBatchSnapshotV1.SessionContext
    typealias ThreadContext = WorktreeAnnotationBatchSnapshotV1.ThreadContext
    typealias Origin = WorktreeAnnotationBatchSnapshotV1.Origin
    typealias ExcerptLine = WorktreeAnnotationBatchSnapshotV1.ExcerptLine
    typealias Source = WorktreeAnnotationBatchSnapshotV1.Source
    typealias ComparisonOrigin = WorktreeAnnotationBatchSnapshotV1.ComparisonOrigin
    typealias ComparisonTarget = WorktreeAnnotationBatchSnapshotV1.ComparisonTarget
    typealias Coordinate = WorktreeAnnotationBatchSnapshotV1.Coordinate
    typealias Placement = WorktreeAnnotationBatchSnapshotV1.Placement

    let schema: String
    let formatVersion: Int
    let batchID: WorktreeAnnotationOutputAttemptID
    let createdAt: String
    let session: SessionContext
    let entries: [Entry]

    struct Entry: Codable, Equatable, Sendable {
        let batchOrdinal: Int
        let thread: ThreadContext
        let message: MessageContext

        private enum CodingKeys: String, CodingKey, CaseIterable { case batchOrdinal, message, thread }

        init(batchOrdinal: Int, thread: ThreadContext, message: MessageContext) {
            self.batchOrdinal = batchOrdinal
            self.thread = thread
            self.message = message
        }

        init(from decoder: Decoder) throws {
            try rejectUnknownBatchKeys(decoder, CodingKeys.self, contract: "v2 batch entry")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            batchOrdinal = try container.decode(Int.self, forKey: .batchOrdinal)
            thread = try container.decode(ThreadContext.self, forKey: .thread)
            message = try container.decode(MessageContext.self, forKey: .message)
        }

        var threadID: WorktreeAnnotationThreadID { thread.threadID }
        var messageID: WorktreeAnnotationMessageID { message.messageID }
        var messageOrdinal: Int { message.messageOrdinal }
        var savedRevision: Int { message.savedRevision }
        var bodyMarkdown: String { message.bodyMarkdown }
        var resolution: WorktreeAnnotationThreadResolution { thread.resolution }
        var origin: Origin { thread.origin }
        var placement: Placement { thread.placement }
    }

    struct MessageContext: Codable, Equatable, Sendable {
        struct Author: Codable, Equatable, Sendable {
            enum Kind: String, Codable, Sendable {
                case human
                case agent

                init(_ authorKind: WorktreeAnnotationAuthorKind) {
                    switch authorKind {
                    case .human: self = .human
                    case .agent: self = .agent
                    }
                }

                var domainValue: WorktreeAnnotationAuthorKind {
                    switch self {
                    case .human: .human
                    case .agent: .agent
                    }
                }
            }

            let kind: Kind

            private enum CodingKeys: String, CodingKey, CaseIterable { case kind }

            init(kind: Kind) {
                self.kind = kind
            }

            init(from decoder: Decoder) throws {
                try rejectUnknownBatchKeys(decoder, CodingKeys.self, contract: "v2 batch author")
                let container = try decoder.container(keyedBy: CodingKeys.self)
                kind = try container.decode(Kind.self, forKey: .kind)
            }
        }

        let messageID: WorktreeAnnotationMessageID
        let messageOrdinal: Int
        let author: Author
        let savedRevision: Int
        let bodyMarkdown: String

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case author, bodyMarkdown, messageOrdinal, savedRevision
            case messageID = "messageId"
        }

        init(
            messageID: WorktreeAnnotationMessageID,
            messageOrdinal: Int,
            authorKind: WorktreeAnnotationAuthorKind,
            savedRevision: Int,
            bodyMarkdown: String
        ) {
            self.messageID = messageID
            self.messageOrdinal = messageOrdinal
            author = Author(kind: .init(authorKind))
            self.savedRevision = savedRevision
            self.bodyMarkdown = bodyMarkdown
        }

        init(from decoder: Decoder) throws {
            try rejectUnknownBatchKeys(decoder, CodingKeys.self, contract: "v2 batch message")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            messageID = try container.decode(WorktreeAnnotationMessageID.self, forKey: .messageID)
            messageOrdinal = try container.decode(Int.self, forKey: .messageOrdinal)
            author = try container.decode(Author.self, forKey: .author)
            savedRevision = try container.decode(Int.self, forKey: .savedRevision)
            bodyMarkdown = try container.decode(String.self, forKey: .bodyMarkdown)
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case createdAt, entries, formatVersion, schema, session
        case batchID = "batchId"
    }

    init(
        schema: String = Self.schema,
        formatVersion: Int = currentFormatVersion,
        batchID: WorktreeAnnotationOutputAttemptID,
        createdAt: String,
        session: SessionContext,
        entries: [Entry]
    ) {
        self.schema = schema
        self.formatVersion = formatVersion
        self.batchID = batchID
        self.createdAt = createdAt
        self.session = session
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        try rejectUnknownBatchKeys(decoder, CodingKeys.self, contract: "v2 annotation batch")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        batchID = try container.decode(WorktreeAnnotationOutputAttemptID.self, forKey: .batchID)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        session = try container.decode(SessionContext.self, forKey: .session)
        entries = try container.decode([Entry].self, forKey: .entries)
    }
}

enum WorktreeAnnotationStoredBatchDocument: Equatable, Sendable {
    case v1(WorktreeAnnotationBatchSnapshotV1)
    case v2(WorktreeAnnotationBatchSnapshotV2)

    var formatVersion: Int {
        switch self {
        case .v1(let snapshot): snapshot.formatVersion
        case .v2(let snapshot): snapshot.formatVersion
        }
    }

    var sessionID: WorktreeAnnotationSessionID {
        switch self {
        case .v1(let snapshot): snapshot.session.sessionID
        case .v2(let snapshot): snapshot.session.sessionID
        }
    }

    var messageIDs: [WorktreeAnnotationMessageID] {
        switch self {
        case .v1(let snapshot): snapshot.entries.map(\.messageID)
        case .v2(let snapshot): snapshot.entries.map(\.messageID)
        }
    }

    var savedRevisions: [Int] {
        switch self {
        case .v1(let snapshot): snapshot.entries.map(\.savedRevision)
        case .v2(let snapshot): snapshot.entries.map(\.savedRevision)
        }
    }

    var batchOrdinals: [Int] {
        switch self {
        case .v1(let snapshot): snapshot.entries.map(\.batchOrdinal)
        case .v2(let snapshot): snapshot.entries.map(\.batchOrdinal)
        }
    }

    static func decodeJSON(
        _ data: Data,
        persistedFormatVersion: Int
    ) throws -> Self {
        switch persistedFormatVersion {
        case WorktreeAnnotationBatchSnapshotV1.currentFormatVersion:
            let snapshot = try BridgeProductStrictJSON.decode(
                WorktreeAnnotationBatchSnapshotV1.self,
                from: data,
                memberVocabulary: WorktreeAnnotationBatchJSON.memberVocabulary,
                maximumInputBytes: nil
            )
            try WorktreeAnnotationBatchProjector.validateV1(snapshot)
            return .v1(snapshot)
        case WorktreeAnnotationBatchSnapshotV2.currentFormatVersion:
            return .v2(try WorktreeAnnotationBatchProjector.decodeJSON(data))
        default:
            throw WorktreeAnnotationBatchProjectorError.unsupportedFormatVersion
        }
    }

    func jsonData() throws -> Data {
        switch self {
        case .v1(let snapshot):
            try WorktreeAnnotationBatchProjector.jsonData(forV1: snapshot)
        case .v2(let snapshot):
            try WorktreeAnnotationBatchProjector.jsonData(for: snapshot)
        }
    }
}
