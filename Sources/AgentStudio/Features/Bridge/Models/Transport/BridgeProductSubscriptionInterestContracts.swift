import Foundation

struct BridgeProductReviewMetadataInterestAddition: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case itemId
        case lane
    }

    let itemId: String
    let lane: BridgeProductDemandLane

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "review metadata interest addition"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.itemId = try container.decode(String.self, forKey: .itemId)
        self.lane = try container.decode(BridgeProductDemandLane.self, forKey: .lane)
        try BridgeProductContractDecoding.validateIdentifier(itemId, codingPath: decoder.codingPath)
    }
}

struct BridgeProductReviewMetadataInterestDelta: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case add
        case removeItemIds
        case subscriptionKind
    }

    let add: [BridgeProductReviewMetadataInterestAddition]
    let removeItemIds: [String]

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "review metadata interest delta"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.add = try container.decode([BridgeProductReviewMetadataInterestAddition].self, forKey: .add)
        self.removeItemIds = try container.decode([String].self, forKey: .removeItemIds)
        guard try container.decode(BridgeProductSubscriptionKind.self, forKey: .subscriptionKind) == .reviewMetadata
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "Review metadata interest delta kind must be review.metadata",
                codingPath: decoder.codingPath
            )
        }
        for itemId in removeItemIds {
            try BridgeProductContractDecoding.validateIdentifier(itemId, codingPath: decoder.codingPath)
        }
        try BridgeProductSubscriptionDeltaValidation.validateCollectionPair(
            additions: add.map(\.itemId),
            removals: removeItemIds,
            codingPath: decoder.codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(add, forKey: .add)
        try container.encode(removeItemIds, forKey: .removeItemIds)
        try container.encode(BridgeProductSubscriptionKind.reviewMetadata, forKey: .subscriptionKind)
    }
}

struct BridgeProductFileMetadataInterestAddition: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case lane
        case path
    }

    let lane: BridgeProductDemandLane
    let path: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "file metadata interest addition"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.lane = try container.decode(BridgeProductDemandLane.self, forKey: .lane)
        self.path = try container.decode(String.self, forKey: .path)
        try BridgeProductContractDecoding.validateDisplayPath(path, codingPath: decoder.codingPath)
    }
}

struct BridgeProductFileMetadataInterestDelta: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case add
        case addPathScope
        case removePathScope
        case removePaths
        case subscriptionKind
    }

    let add: [BridgeProductFileMetadataInterestAddition]
    let addPathScope: [String]
    let removePathScope: [String]
    let removePaths: [String]

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "file metadata interest delta"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.add = try container.decode([BridgeProductFileMetadataInterestAddition].self, forKey: .add)
        self.addPathScope = try container.decode([String].self, forKey: .addPathScope)
        self.removePathScope = try container.decode([String].self, forKey: .removePathScope)
        self.removePaths = try container.decode([String].self, forKey: .removePaths)
        guard try container.decode(BridgeProductSubscriptionKind.self, forKey: .subscriptionKind) == .fileMetadata
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "File metadata interest delta kind must be file.metadata",
                codingPath: decoder.codingPath
            )
        }
        try BridgeProductSubscriptionDeltaValidation.validateCollectionPair(
            additions: add.map(\.path),
            removals: removePaths,
            codingPath: decoder.codingPath
        )
        try BridgeProductSubscriptionDeltaValidation.validateCollectionPair(
            additions: addPathScope,
            removals: removePathScope,
            codingPath: decoder.codingPath
        )
        for path in addPathScope + removePathScope + removePaths {
            try BridgeProductContractDecoding.validateDisplayPath(path, codingPath: decoder.codingPath)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(add, forKey: .add)
        try container.encode(addPathScope, forKey: .addPathScope)
        try container.encode(removePathScope, forKey: .removePathScope)
        try container.encode(removePaths, forKey: .removePaths)
        try container.encode(BridgeProductSubscriptionKind.fileMetadata, forKey: .subscriptionKind)
    }
}

enum BridgeProductSubscriptionInterestDelta: Codable, Equatable, Sendable {
    case fileMetadata(BridgeProductFileMetadataInterestDelta)
    case reviewMetadata(BridgeProductReviewMetadataInterestDelta)

    private enum CodingKeys: String, CodingKey {
        case subscriptionKind
    }

    var itemCount: Int {
        switch self {
        case .fileMetadata(let delta):
            delta.add.count + delta.addPathScope.count + delta.removePathScope.count + delta.removePaths.count
        case .reviewMetadata(let delta):
            delta.add.count + delta.removeItemIds.count
        }
    }

    var subscriptionKind: BridgeProductSubscriptionKind {
        switch self {
        case .fileMetadata: .fileMetadata
        case .reviewMetadata: .reviewMetadata
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(BridgeProductSubscriptionKind.self, forKey: .subscriptionKind) {
        case .fileMetadata:
            self = .fileMetadata(try BridgeProductFileMetadataInterestDelta(from: decoder))
        case .reviewMetadata:
            self = .reviewMetadata(try BridgeProductReviewMetadataInterestDelta(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .fileMetadata(let delta):
            try delta.encode(to: encoder)
        case .reviewMetadata(let delta):
            try delta.encode(to: encoder)
        }
    }
}

private enum BridgeProductSubscriptionDeltaValidation {
    static func validateCollectionPair(
        additions: [String],
        removals: [String],
        codingPath: [any CodingKey]
    ) throws {
        try validateBoundedUniqueCollection(additions, codingPath: codingPath)
        try validateBoundedUniqueCollection(removals, codingPath: codingPath)
        let additionIdentities = Set(additions.map { Data($0.utf8) })
        let removalIdentities = Set(removals.map { Data($0.utf8) })
        guard additionIdentities.isDisjoint(with: removalIdentities) else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product subscription delta cannot add and remove the same member",
                codingPath: codingPath
            )
        }
        try BridgeProductContractDecoding.validateMaximum(
            additions.count + removals.count,
            maximum: BridgeProductWireContract.maximumSubscriptionDeltaItemCount,
            name: "subscription delta item count",
            codingPath: codingPath
        )
    }

    private static func validateBoundedUniqueCollection(
        _ values: [String],
        codingPath: [any CodingKey]
    ) throws {
        try BridgeProductContractDecoding.validateCollectionCount(
            values.count,
            maximum: BridgeProductWireContract.maximumSubscriptionDeltaItemCount,
            name: "subscription delta collection",
            codingPath: codingPath
        )
        guard Set(values.map { Data($0.utf8) }).count == values.count else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product subscription delta members must be unique",
                codingPath: codingPath
            )
        }
    }
}
