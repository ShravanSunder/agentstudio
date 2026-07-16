import Foundation

struct BridgeContentHandle: Codable, Equatable, Sendable {
    enum Role: String, Codable, Equatable, Hashable, Sendable {
        case base
        case head
        case diff
        case file
    }

    let handleId: String
    let itemId: String
    let role: Role
    let endpointId: String
    let reviewGeneration: BridgeReviewGeneration
    let contentHash: String
    let contentHashAlgorithm: String
    let cacheKey: String
    let mimeType: String
    let language: String?
    let sizeBytes: Int
    let sizeBytesIsExact: Bool
    let isBinary: Bool

    init(
        handleId: String,
        itemId: String,
        role: Role,
        endpointId: String,
        reviewGeneration: BridgeReviewGeneration,
        contentHash: String,
        contentHashAlgorithm: String,
        cacheKey: String,
        mimeType: String,
        language: String?,
        sizeBytes: Int,
        sizeBytesIsExact: Bool = true,
        isBinary: Bool
    ) {
        self.handleId = handleId
        self.itemId = itemId
        self.role = role
        self.endpointId = endpointId
        self.reviewGeneration = reviewGeneration
        self.contentHash = contentHash
        self.contentHashAlgorithm = contentHashAlgorithm
        self.cacheKey = cacheKey
        self.mimeType = mimeType
        self.language = language
        self.sizeBytes = sizeBytes
        self.sizeBytesIsExact = sizeBytesIsExact
        self.isBinary = isBinary
    }

    enum CodingKeys: String, CodingKey {
        case handleId
        case itemId
        case role
        case endpointId
        case reviewGeneration
        case contentHash
        case contentHashAlgorithm
        case cacheKey
        case mimeType
        case language
        case sizeBytes
        case sizeBytesIsExact
        case isBinary
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            handleId: container.decode(String.self, forKey: .handleId),
            itemId: container.decode(String.self, forKey: .itemId),
            role: container.decode(Role.self, forKey: .role),
            endpointId: container.decode(String.self, forKey: .endpointId),
            reviewGeneration: container.decode(BridgeReviewGeneration.self, forKey: .reviewGeneration),
            contentHash: container.decode(String.self, forKey: .contentHash),
            contentHashAlgorithm: container.decode(String.self, forKey: .contentHashAlgorithm),
            cacheKey: container.decode(String.self, forKey: .cacheKey),
            mimeType: container.decode(String.self, forKey: .mimeType),
            language: container.decodeIfPresent(String.self, forKey: .language),
            sizeBytes: container.decode(Int.self, forKey: .sizeBytes),
            sizeBytesIsExact: container.decodeIfPresent(Bool.self, forKey: .sizeBytesIsExact) ?? true,
            isBinary: container.decode(Bool.self, forKey: .isBinary)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(handleId, forKey: .handleId)
        try container.encode(itemId, forKey: .itemId)
        try container.encode(role, forKey: .role)
        try container.encode(endpointId, forKey: .endpointId)
        try container.encode(reviewGeneration, forKey: .reviewGeneration)
        try container.encode(contentHash, forKey: .contentHash)
        try container.encode(contentHashAlgorithm, forKey: .contentHashAlgorithm)
        try container.encode(cacheKey, forKey: .cacheKey)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encode(sizeBytes, forKey: .sizeBytes)
        try container.encode(sizeBytesIsExact, forKey: .sizeBytesIsExact)
        try container.encode(isBinary, forKey: .isBinary)
    }
}
