import Foundation

/// Command-confirmed origin facts, deliberately separate from projected placement.
struct BridgeProductAnnotationCommandThreadContext: Codable, Equatable, Sendable {
    let diffSide: WorktreeAnnotationDiffSide?
    let endLine: Int
    let path: String
    let resolution: WorktreeAnnotationThreadResolution
    let scope: WorktreeAnnotationThreadScope
    let sourceIdentity: String
    let sourceRole: WorktreeAnnotationSourceRole
    let startLine: Int
    let threadId: UUID

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case diffSide, endLine, path, resolution, scope, sourceIdentity, sourceRole, startLine, threadId
    }

    init(_ thread: WorktreeAnnotationThread) throws {
        guard case .located(let origin) = thread.origin else {
            throw BridgeProductWorktreeAnnotationProjectionError.unsupportedThreadOrigin
        }
        diffSide = origin.diffSide
        endLine = origin.endLine
        path = origin.repositoryRelativePath
        resolution = thread.resolution
        scope = .located
        sourceIdentity = origin.sourceIdentity
        sourceRole = origin.sourceRole
        startLine = origin.startLine
        threadId = thread.id.rawValue
    }

    init(from decoder: Decoder) throws {
        try rejectReceiptUnknownKeys(decoder, keys: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        diffSide = try BridgeProductContractDecoding.decodeRequiredNullable(
            WorktreeAnnotationDiffSide.self, forKey: .diffSide, from: container, codingPath: decoder.codingPath)
        endLine = try container.decode(Int.self, forKey: .endLine)
        path = try container.decode(String.self, forKey: .path)
        resolution = try container.decode(WorktreeAnnotationThreadResolution.self, forKey: .resolution)
        scope = try container.decode(WorktreeAnnotationThreadScope.self, forKey: .scope)
        sourceIdentity = try container.decode(String.self, forKey: .sourceIdentity)
        sourceRole = try container.decode(WorktreeAnnotationSourceRole.self, forKey: .sourceRole)
        startLine = try container.decode(Int.self, forKey: .startLine)
        threadId = try decodeReceiptID(container, key: .threadId, decoder: decoder)
        try BridgeProductContractDecoding.validateDisplayPath(path, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(sourceIdentity, codingPath: decoder.codingPath)
        guard scope == .located, startLine > 0, endLine >= startLine else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation command context must be a located range", codingPath: decoder.codingPath)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(diffSide, forKey: .diffSide)
        try container.encode(endLine, forKey: .endLine)
        try container.encode(path, forKey: .path)
        try container.encode(resolution, forKey: .resolution)
        try container.encode(scope, forKey: .scope)
        try container.encode(sourceIdentity, forKey: .sourceIdentity)
        try container.encode(sourceRole, forKey: .sourceRole)
        try container.encode(startLine, forKey: .startLine)
        try container.encode(BridgeProductReviewPublicationIdContract.encode(threadId), forKey: .threadId)
    }
}

struct BridgeProductAnnotationMessageRemoval: Equatable, Sendable {
    let sessionId: UUID
    let sessionRevision: Int
    let threadId: UUID
    let threadRevision: Int?
    let messageId: UUID
    let removedMessageRevision: Int
}

enum BridgeProductWorktreeAnnotationMessageReceiptDTO: Codable, Equatable, Sendable {
    case message(
        context: BridgeProductAnnotationCommandThreadContext,
        message: BridgeProductWorktreeAnnotationMessageEntry)
    case messageRemoved(BridgeProductAnnotationMessageRemoval)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, context, message, sessionId, sessionRevision, threadId, threadRevision, messageId,
            removedMessageRevision
    }

    var sessionId: UUID {
        switch self {
        case .message(_, let message): message.sessionId
        case .messageRemoved(let removal): removal.sessionId
        }
    }

    init(
        session: WorktreeAnnotationSession, thread: WorktreeAnnotationThread, message: WorktreeAnnotationMessage
    ) throws {
        self = .message(
            context: try .init(thread),
            message: try .init(message: message, session: session, thread: thread))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "message":
            try rejectReceiptUnknownKeys(decoder, keys: [CodingKeys.kind, .context, .message])
            let context = try container.decode(
                BridgeProductAnnotationCommandThreadContext.self, forKey: .context)
            let message = try container.decode(BridgeProductWorktreeAnnotationMessageEntry.self, forKey: .message)
            guard context.threadId == message.threadId else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Annotation receipt context and message must name the same thread", codingPath: decoder.codingPath)
            }
            for identifier in [message.messageId, message.threadId, message.sessionId] {
                _ = try BridgeProductReviewPublicationIdContract.decode(
                    BridgeProductReviewPublicationIdContract.encode(identifier), codingPath: decoder.codingPath)
            }
            self = .message(context: context, message: message)
        case "message_removed":
            try rejectReceiptUnknownKeys(
                decoder,
                keys: [
                    CodingKeys.kind, .sessionId, .sessionRevision, .threadId, .threadRevision, .messageId,
                    .removedMessageRevision,
                ])
            let sessionRevision = try container.decode(Int.self, forKey: .sessionRevision)
            let threadRevision = try BridgeProductContractDecoding.decodeRequiredNullable(
                Int.self, forKey: .threadRevision, from: container, codingPath: decoder.codingPath)
            let removedMessageRevision = try container.decode(Int.self, forKey: .removedMessageRevision)
            for revision in [sessionRevision, removedMessageRevision, threadRevision].compactMap({ $0 }) {
                try BridgeProductContractDecoding.validateNonnegative(
                    revision, name: "receipt revision", codingPath: decoder.codingPath)
            }
            self = .messageRemoved(
                .init(
                    sessionId: try decodeReceiptID(container, key: .sessionId, decoder: decoder),
                    sessionRevision: sessionRevision,
                    threadId: try decodeReceiptID(container, key: .threadId, decoder: decoder),
                    threadRevision: threadRevision,
                    messageId: try decodeReceiptID(container, key: .messageId, decoder: decoder),
                    removedMessageRevision: removedMessageRevision))
        default:
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid annotation command receipt kind", codingPath: decoder.codingPath)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .message(let context, let message):
            try container.encode("message", forKey: .kind)
            try container.encode(context, forKey: .context)
            try container.encode(message, forKey: .message)
        case .messageRemoved(let removal):
            try container.encode("message_removed", forKey: .kind)
            try container.encode(BridgeProductReviewPublicationIdContract.encode(removal.sessionId), forKey: .sessionId)
            try container.encode(removal.sessionRevision, forKey: .sessionRevision)
            try container.encode(BridgeProductReviewPublicationIdContract.encode(removal.threadId), forKey: .threadId)
            try container.encode(removal.threadRevision, forKey: .threadRevision)
            try container.encode(BridgeProductReviewPublicationIdContract.encode(removal.messageId), forKey: .messageId)
            try container.encode(removal.removedMessageRevision, forKey: .removedMessageRevision)
        }
    }
}

private func rejectReceiptUnknownKeys<ReceiptKey: CodingKey & RawRepresentable>(
    _ decoder: Decoder, keys: [ReceiptKey]
) throws where ReceiptKey.RawValue == String {
    try BridgeProductContractDecoding.rejectUnknownKeys(
        from: decoder, allowedKeys: Set(keys.map(\.rawValue)), contract: "annotation command receipt")
}

private func decodeReceiptID<ReceiptKey: CodingKey>(
    _ container: KeyedDecodingContainer<ReceiptKey>, key: ReceiptKey, decoder: Decoder
) throws -> UUID {
    try BridgeProductReviewPublicationIdContract.decode(
        container.decode(String.self, forKey: key), codingPath: decoder.codingPath + [key])
}
