import Foundation

struct BridgeProductReviewMarkFileViewedRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case itemId
    }

    let itemId: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "review.markFileViewed request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.itemId = try container.decode(String.self, forKey: .itemId)
        try BridgeProductContractDecoding.validateIdentifier(itemId, codingPath: decoder.codingPath)
    }
}

enum BridgeProductCallRequest: Codable, Equatable, Sendable {
    case reviewMarkFileViewed(BridgeProductReviewMarkFileViewedRequest)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case method
        case request
    }

    var method: String {
        switch self {
        case .reviewMarkFileViewed: "review.markFileViewed"
        }
    }

    var surface: BridgeProductSurface {
        switch self {
        case .reviewMarkFileViewed: .review
        }
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge product call request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .method) {
        case "review.markFileViewed":
            self = .reviewMarkFileViewed(
                try container.decode(BridgeProductReviewMarkFileViewedRequest.self, forKey: .request)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .method,
                in: container,
                debugDescription: "Unknown Bridge product call method"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(method, forKey: .method)
        switch self {
        case .reviewMarkFileViewed(let request):
            try container.encode(request, forKey: .request)
        }
    }
}

enum BridgeProductCallResult: Codable, Equatable, Sendable {
    case reviewMarkFileViewed

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case method
        case result
    }

    var method: String {
        switch self {
        case .reviewMarkFileViewed: "review.markFileViewed"
        }
    }

    var surface: BridgeProductSurface {
        switch self {
        case .reviewMarkFileViewed: .review
        }
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge product call result"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .method) {
        case "review.markFileViewed":
            try BridgeProductContractDecoding.decodeRequiredNull(
                forKey: .result,
                from: container,
                codingPath: decoder.codingPath
            )
            self = .reviewMarkFileViewed
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .method,
                in: container,
                debugDescription: "Unknown Bridge product call result method"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(method, forKey: .method)
        try container.encodeNil(forKey: .result)
    }
}
