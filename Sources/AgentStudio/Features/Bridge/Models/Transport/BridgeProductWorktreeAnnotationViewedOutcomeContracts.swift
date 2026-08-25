import Foundation

enum BridgeProductWorktreeAnnotationViewedResultDTO: Codable, Equatable, Sendable {
    case viewed(
        messageId: UUID,
        savedRevision: Int,
        committedSessionRevision: Int,
        disposition: ViewedDisposition
    )
    case notViewed(
        messageId: UUID,
        expectedSavedRevision: Int,
        disposition: NotViewedDisposition
    )

    enum ViewedDisposition: String, Codable, Equatable, Sendable {
        case changed
        case alreadyViewed = "already_viewed"
    }

    enum NotViewedDisposition: String, Codable, Equatable, Sendable {
        case stale
        case notAgent = "not_agent"
        case notFound = "not_found"
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case committedSessionRevision
        case disposition
        case expectedSavedRevision
        case kind
        case messageId
        case savedRevision
    }

    var revisionIdentity: String {
        switch self {
        case .viewed(let messageId, let savedRevision, _, _):
            "\(messageId.uuidString.lowercased()):\(savedRevision)"
        case .notViewed(let messageId, let expectedSavedRevision, _):
            "\(messageId.uuidString.lowercased()):\(expectedSavedRevision)"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        let allowedKeys: Set<String> =
            switch kind {
            case "viewed":
                ["committedSessionRevision", "disposition", "kind", "messageId", "savedRevision"]
            case "not_viewed":
                ["disposition", "expectedSavedRevision", "kind", "messageId"]
            default:
                []
            }
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: allowedKeys,
            contract: "viewed annotation result"
        )
        let messageId = try BridgeProductReviewPublicationIdContract.decode(
            container.decode(String.self, forKey: .messageId),
            codingPath: decoder.codingPath
        )
        switch kind {
        case "viewed":
            let savedRevision = try container.decode(Int.self, forKey: .savedRevision)
            let committedSessionRevision = try container.decode(Int.self, forKey: .committedSessionRevision)
            guard savedRevision > 0, committedSessionRevision >= 0 else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Viewed annotation revisions are invalid",
                    codingPath: decoder.codingPath
                )
            }
            self = .viewed(
                messageId: messageId,
                savedRevision: savedRevision,
                committedSessionRevision: committedSessionRevision,
                disposition: try container.decode(ViewedDisposition.self, forKey: .disposition)
            )
        case "not_viewed":
            let expectedSavedRevision = try container.decode(Int.self, forKey: .expectedSavedRevision)
            guard expectedSavedRevision > 0 else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Expected saved revision must be positive",
                    codingPath: decoder.codingPath
                )
            }
            self = .notViewed(
                messageId: messageId,
                expectedSavedRevision: expectedSavedRevision,
                disposition: try container.decode(NotViewedDisposition.self, forKey: .disposition)
            )
        default:
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid viewed annotation result kind",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .viewed(let messageId, let savedRevision, let committedSessionRevision, let disposition):
            try container.encode(committedSessionRevision, forKey: .committedSessionRevision)
            try container.encode(disposition, forKey: .disposition)
            try container.encode("viewed", forKey: .kind)
            try container.encode(BridgeProductReviewPublicationIdContract.encode(messageId), forKey: .messageId)
            try container.encode(savedRevision, forKey: .savedRevision)
        case .notViewed(let messageId, let expectedSavedRevision, let disposition):
            try container.encode(disposition, forKey: .disposition)
            try container.encode(expectedSavedRevision, forKey: .expectedSavedRevision)
            try container.encode("not_viewed", forKey: .kind)
            try container.encode(BridgeProductReviewPublicationIdContract.encode(messageId), forKey: .messageId)
        }
    }
}

extension BridgeProductWorktreeAnnotationViewedResultDTO {
    init(_ result: WorktreeAnnotationViewedResult) {
        switch result {
        case .viewed(let messageID, let savedRevision, let committedSessionRevision, let disposition):
            self = .viewed(
                messageId: messageID.rawValue,
                savedRevision: savedRevision,
                committedSessionRevision: committedSessionRevision,
                disposition: disposition == .changed ? .changed : .alreadyViewed
            )
        case .notViewed(let messageID, let expectedSavedRevision, let disposition):
            let transportDisposition: NotViewedDisposition =
                switch disposition {
                case .stale: .stale
                case .notAgent: .notAgent
                case .notFound: .notFound
                }
            self = .notViewed(
                messageId: messageID.rawValue,
                expectedSavedRevision: expectedSavedRevision,
                disposition: transportDisposition
            )
        }
    }
}
