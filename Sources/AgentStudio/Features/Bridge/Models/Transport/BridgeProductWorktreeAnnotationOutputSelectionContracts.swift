import Foundation

extension BridgeProductWorktreeAnnotationOperation {
    enum OutputKind: String, Codable, Equatable, Sendable {
        case clipboardMarkdown
        case jsonFile
    }

    enum OutputSelectionMode: String, Codable, Equatable, Sendable {
        case explicit
        case allEligible
    }

    struct OutputSelectionBeginBody: Codable, Equatable, Sendable {
        let outputKind: OutputKind
        let selectionMode: OutputSelectionMode
        let sessionId: UUID
        let transferId: String
    }

    struct OutputSelectionChunkBody: Codable, Equatable, Sendable {
        let messageIds: [UUID]
        let ordinal: Int
        let selectionMode: OutputSelectionMode
        let sessionId: UUID
        let transferId: String
    }

    struct OutputSelectionTerminalBody: Codable, Equatable, Sendable {
        let selectionMode: OutputSelectionMode
        let sessionId: UUID
        let transferId: String
    }

    enum OutputCandidateCursor: Codable, Equatable, Sendable {
        case start
        case after(flatOrdinal: Int, messageID: UUID)

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case flatOrdinal
            case kind
            case messageId
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(String.self, forKey: .kind)
            let allowedKeys: Set<String>
            switch kind {
            case "start":
                allowedKeys = [CodingKeys.kind.rawValue]
                self = .start
            case "after":
                allowedKeys = Set(CodingKeys.allCases.map(\.rawValue))
                let flatOrdinal = try container.decode(Int.self, forKey: .flatOrdinal)
                guard flatOrdinal >= 0 else {
                    throw BridgeProductContractDecoding.invalidValue(
                        "Annotation output cursor ordinal must be nonnegative",
                        codingPath: decoder.codingPath
                    )
                }
                self = .after(
                    flatOrdinal: flatOrdinal,
                    messageID: try BridgeProductReviewPublicationIdContract.decode(
                        container.decode(String.self, forKey: .messageId),
                        codingPath: decoder.codingPath
                    )
                )
            default:
                throw BridgeProductContractDecoding.invalidValue(
                    "Invalid annotation output candidate cursor",
                    codingPath: decoder.codingPath
                )
            }
            try BridgeProductContractDecoding.rejectUnknownKeys(
                from: decoder,
                allowedKeys: allowedKeys,
                contract: "annotation output candidate cursor"
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .start:
                try container.encode("start", forKey: .kind)
            case .after(let flatOrdinal, let messageID):
                try container.encode(flatOrdinal, forKey: .flatOrdinal)
                try container.encode("after", forKey: .kind)
                try container.encode(
                    BridgeProductReviewPublicationIdContract.encode(messageID),
                    forKey: .messageId
                )
            }
        }
    }

}

struct BridgeProductAnnotationCandidateQuery: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case cursor
        case expectedSessionRevision
        case limit
        case sessionId
    }

    let cursor: BridgeProductWorktreeAnnotationOperation.OutputCandidateCursor
    let expectedSessionRevision: Int
    let limit: Int
    let sessionId: UUID

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "annotation output candidate query"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cursor = try container.decode(
            BridgeProductWorktreeAnnotationOperation.OutputCandidateCursor.self,
            forKey: .cursor
        )
        expectedSessionRevision = try container.decode(Int.self, forKey: .expectedSessionRevision)
        limit = try container.decode(Int.self, forKey: .limit)
        sessionId = try BridgeProductReviewPublicationIdContract.decode(
            container.decode(String.self, forKey: .sessionId),
            codingPath: decoder.codingPath
        )
        guard expectedSessionRevision >= 0, (1...16).contains(limit) else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation output candidate query is invalid",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cursor, forKey: .cursor)
        try container.encode(expectedSessionRevision, forKey: .expectedSessionRevision)
        try container.encode(limit, forKey: .limit)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(sessionId),
            forKey: .sessionId
        )
    }
}

struct BridgeProductWorktreeAnnotationOutputCandidateDTO: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case authoredAt
        case endLine
        case excerpt
        case flatOrdinal
        case location
        case messageId
        case path
        case placement
        case state
        case startLine
        case threadId
    }

    let authoredAt: Date
    let endLine: Int
    let excerpt: String
    let flatOrdinal: Int
    let location: WorktreeAnnotationOutputCandidateLocation
    let messageId: UUID
    let path: String
    let placement: WorktreeAnnotationPlacement
    let state: WorktreeAnnotationOutputCandidateState
    let startLine: Int
    let threadId: UUID

    init(_ candidate: WorktreeAnnotationOutputCandidate) {
        authoredAt = candidate.authoredAt
        endLine = candidate.endLine
        excerpt = candidate.excerpt
        flatOrdinal = candidate.flatOrdinal
        location = candidate.location
        messageId = candidate.messageID.rawValue
        path = candidate.path
        placement = candidate.placement
        state = candidate.state
        startLine = candidate.startLine
        threadId = candidate.threadID.rawValue
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "annotation output candidate"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authoredAt = try container.decode(Date.self, forKey: .authoredAt)
        endLine = try container.decode(Int.self, forKey: .endLine)
        excerpt = try container.decode(String.self, forKey: .excerpt)
        flatOrdinal = try container.decode(Int.self, forKey: .flatOrdinal)
        location = try container.decode(WorktreeAnnotationOutputCandidateLocation.self, forKey: .location)
        messageId = try container.decode(UUID.self, forKey: .messageId)
        path = try container.decode(String.self, forKey: .path)
        placement = try container.decode(WorktreeAnnotationPlacement.self, forKey: .placement)
        startLine = try container.decode(Int.self, forKey: .startLine)
        state = try container.decode(WorktreeAnnotationOutputCandidateState.self, forKey: .state)
        threadId = try container.decode(UUID.self, forKey: .threadId)
        guard !path.isEmpty,
            path.utf8.count <= 4096,
            excerpt.utf8.count <= 512,
            flatOrdinal >= 0,
            startLine > 0,
            endLine >= startLine
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation output candidate is invalid",
                codingPath: decoder.codingPath
            )
        }
    }
}

struct BridgeProductAnnotationCandidatePageDTO: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case candidates
        case eligibleMessageCount
        case eligibleWithoutInlinePlacementCount
        case nextCursor
        case sessionId
        case sessionRevision
    }

    let candidates: [BridgeProductWorktreeAnnotationOutputCandidateDTO]
    let eligibleMessageCount: Int
    let eligibleWithoutInlinePlacementCount: Int
    let nextCursor: BridgeProductWorktreeAnnotationOperation.OutputCandidateCursor?
    let sessionId: UUID
    let sessionRevision: Int

    init(_ page: WorktreeAnnotationOutputCandidatePage) {
        candidates = page.candidates.map(BridgeProductWorktreeAnnotationOutputCandidateDTO.init)
        eligibleMessageCount = page.eligibleMessageCount
        eligibleWithoutInlinePlacementCount = page.eligibleWithoutInlinePlacementCount
        nextCursor = page.nextCursor.map {
            .after(flatOrdinal: $0.flatOrdinal, messageID: $0.messageID.rawValue)
        }
        sessionId = page.sessionID.rawValue
        sessionRevision = page.sessionRevision
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "annotation output candidate page"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        candidates = try container.decode(
            [BridgeProductWorktreeAnnotationOutputCandidateDTO].self,
            forKey: .candidates
        )
        eligibleMessageCount = try container.decode(Int.self, forKey: .eligibleMessageCount)
        eligibleWithoutInlinePlacementCount = try container.decode(
            Int.self,
            forKey: .eligibleWithoutInlinePlacementCount
        )
        nextCursor = try BridgeProductContractDecoding.decodeRequiredNullable(
            BridgeProductWorktreeAnnotationOperation.OutputCandidateCursor.self,
            forKey: .nextCursor,
            from: container,
            codingPath: decoder.codingPath
        )
        sessionId = try container.decode(UUID.self, forKey: .sessionId)
        sessionRevision = try container.decode(Int.self, forKey: .sessionRevision)
        guard candidates.count <= 16,
            eligibleMessageCount >= 0,
            eligibleWithoutInlinePlacementCount >= 0,
            eligibleWithoutInlinePlacementCount <= eligibleMessageCount,
            sessionRevision >= 0
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation output candidate page is invalid",
                codingPath: decoder.codingPath
            )
        }
    }
}
