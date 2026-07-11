import CryptoKit
import Foundation

enum BridgeProductInterestStateEncodingPreflight: Equatable, Sendable {
    case accepted(canonicalByteCount: Int, visitedTextValueCount: Int)
    case exceedsMaximum(
        canonicalByteCountLowerBound: Int,
        maximumCanonicalByteCount: Int,
        visitedTextValueCount: Int
    )
}

enum BridgeProductReviewInterestIdentity {
    static func validate(_ value: String, codingPath: [any CodingKey]) throws {
        guard
            !value.isEmpty,
            value.utf8.count <= BridgeProductWireContract.maximumIdentifierByteLength
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Bridge product review interest identity",
                codingPath: codingPath
            )
        }
    }
}

struct BridgeProductReviewMetadataInterestStateGroup: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case itemIds
        case lane
    }

    let itemIds: [String]
    let lane: BridgeProductDemandLane

    init(itemIds: [String], lane: BridgeProductDemandLane) throws {
        try BridgeProductContractDecoding.validateCollectionCount(
            itemIds.count,
            maximum: BridgeProductWireContract.maximumSubscriptionInterestItemCount,
            name: "review metadata interest-state items",
            codingPath: []
        )
        for itemId in itemIds {
            try BridgeProductReviewInterestIdentity.validate(itemId, codingPath: [])
        }
        self.itemIds = itemIds
        self.lane = lane
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "review metadata interest-state group"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.itemIds = try container.decode([String].self, forKey: .itemIds)
        self.lane = try container.decode(BridgeProductDemandLane.self, forKey: .lane)
        try BridgeProductContractDecoding.validateCollectionCount(
            itemIds.count,
            maximum: BridgeProductWireContract.maximumSubscriptionInterestItemCount,
            name: "review metadata interest-state items",
            codingPath: decoder.codingPath
        )
        for itemId in itemIds {
            try BridgeProductReviewInterestIdentity.validate(itemId, codingPath: decoder.codingPath)
        }
    }
}

struct BridgeProductFileMetadataInterestStateGroup: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case lane
        case paths
    }

    let lane: BridgeProductDemandLane
    let paths: [String]

    init(lane: BridgeProductDemandLane, paths: [String]) throws {
        try BridgeProductContractDecoding.validateCollectionCount(
            paths.count,
            maximum: BridgeProductWireContract.maximumSubscriptionInterestItemCount,
            name: "file metadata interest-state paths",
            codingPath: []
        )
        for path in paths {
            try BridgeProductContractDecoding.validateDisplayPath(path, codingPath: [])
        }
        self.lane = lane
        self.paths = paths
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "file metadata interest-state group"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.lane = try container.decode(BridgeProductDemandLane.self, forKey: .lane)
        self.paths = try container.decode([String].self, forKey: .paths)
        try BridgeProductContractDecoding.validateCollectionCount(
            paths.count,
            maximum: BridgeProductWireContract.maximumSubscriptionInterestItemCount,
            name: "file metadata interest-state paths",
            codingPath: decoder.codingPath
        )
        for path in paths {
            try BridgeProductContractDecoding.validateDisplayPath(path, codingPath: decoder.codingPath)
        }
    }
}

enum BridgeProductSubscriptionInterestState: Codable, Equatable, Sendable {
    case fileMetadata(interests: [BridgeProductFileMetadataInterestStateGroup], pathScope: [String])
    case reviewMetadata(interests: [BridgeProductReviewMetadataInterestStateGroup])

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case interests
        case pathScope
        case subscriptionKind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedState: Self
        switch try container.decode(BridgeProductSubscriptionKind.self, forKey: .subscriptionKind) {
        case .fileMetadata:
            try BridgeProductContractDecoding.rejectUnknownKeys(
                from: decoder,
                allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
                contract: "file metadata interest state"
            )
            let interests = try container.decode(
                [BridgeProductFileMetadataInterestStateGroup].self,
                forKey: .interests
            )
            let pathScope = try container.decode([String].self, forKey: .pathScope)
            decodedState = .fileMetadata(interests: interests, pathScope: pathScope)
        case .reviewMetadata:
            try BridgeProductContractDecoding.rejectUnknownKeys(
                from: decoder,
                allowedKeys: Set([CodingKeys.interests.rawValue, CodingKeys.subscriptionKind.rawValue]),
                contract: "review metadata interest state"
            )
            let interests = try container.decode(
                [BridgeProductReviewMetadataInterestStateGroup].self,
                forKey: .interests
            )
            decodedState = .reviewMetadata(interests: interests)
        }
        try decodedState.validateForCanonicalEncoding(codingPath: decoder.codingPath)
        self = decodedState
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fileMetadata(let interests, let pathScope):
            try container.encode(interests, forKey: .interests)
            try container.encode(pathScope, forKey: .pathScope)
            try container.encode(BridgeProductSubscriptionKind.fileMetadata, forKey: .subscriptionKind)
        case .reviewMetadata(let interests):
            try container.encode(interests, forKey: .interests)
            try container.encode(BridgeProductSubscriptionKind.reviewMetadata, forKey: .subscriptionKind)
        }
    }

    func encodedData() throws -> Data {
        let canonicalByteCount = try validateForCanonicalEncoding()
        var encoded = Data(capacity: canonicalByteCount)
        encoded.append(1)
        encoded.append(subscriptionKindTag)
        let encodedInterests = flattenedInterests.sorted { left, right in
            left.keyBytes.lexicographicallyPrecedes(right.keyBytes)
        }
        try encoded.appendUInt32BigEndian(encodedInterests.count)
        for interest in encodedInterests {
            try encoded.appendLengthPrefixed(interest.keyBytes)
            encoded.append(interest.laneTag)
        }
        if case .fileMetadata(_, let pathScope) = self {
            let encodedPathScope = pathScope.map { Data($0.utf8) }.sorted(by: { left, right in
                left.lexicographicallyPrecedes(right)
            })
            try encoded.appendUInt32BigEndian(encodedPathScope.count)
            for pathBytes in encodedPathScope {
                try encoded.appendLengthPrefixed(pathBytes)
            }
        }
        guard encoded.count == canonicalByteCount else {
            throw BridgeProductContractDecoding.invalidValue(
                "Subscription interest-state encoding length mismatch",
                codingPath: []
            )
        }
        return encoded
    }

    func sha256Hex() throws -> String {
        SHA256.hash(data: try encodedData()).map { String(format: "%02x", $0) }.joined()
    }

    func canonicalEncodingPreflight() -> BridgeProductInterestStateEncodingPreflight {
        var canonicalByteCount: Int
        switch self {
        case .fileMetadata:
            canonicalByteCount = 10
        case .reviewMetadata:
            canonicalByteCount = 6
        }
        var visitedTextValueCount = 0

        func addingTextValue(
            _ value: String,
            perValueOverheadByteCount: Int
        ) -> BridgeProductInterestStateEncodingPreflight? {
            canonicalByteCount += perValueOverheadByteCount + value.utf8.count
            visitedTextValueCount += 1
            guard canonicalByteCount <= BridgeProductWireContract.maximumSubscriptionInterestStateBytes else {
                return .exceedsMaximum(
                    canonicalByteCountLowerBound: canonicalByteCount,
                    maximumCanonicalByteCount: BridgeProductWireContract.maximumSubscriptionInterestStateBytes,
                    visitedTextValueCount: visitedTextValueCount
                )
            }
            return nil
        }

        switch self {
        case .fileMetadata(let interests, let pathScope):
            for interest in interests {
                for path in interest.paths {
                    if let exceeded = addingTextValue(path, perValueOverheadByteCount: 5) {
                        return exceeded
                    }
                }
            }
            for path in pathScope {
                if let exceeded = addingTextValue(path, perValueOverheadByteCount: 4) {
                    return exceeded
                }
            }
        case .reviewMetadata(let interests):
            for interest in interests {
                for itemId in interest.itemIds {
                    if let exceeded = addingTextValue(itemId, perValueOverheadByteCount: 5) {
                        return exceeded
                    }
                }
            }
        }

        return .accepted(
            canonicalByteCount: canonicalByteCount,
            visitedTextValueCount: visitedTextValueCount
        )
    }

    @discardableResult
    func validateForCanonicalEncoding(codingPath: [any CodingKey] = []) throws -> Int {
        switch self {
        case .fileMetadata(let interests, let pathScope):
            try Self.validateFileStateCounts(
                interests: interests,
                pathScope: pathScope,
                codingPath: codingPath
            )
        case .reviewMetadata(let interests):
            try Self.validateReviewStateCounts(interests: interests, codingPath: codingPath)
        }

        let canonicalByteCount: Int
        switch canonicalEncodingPreflight() {
        case .accepted(let acceptedByteCount, _):
            canonicalByteCount = acceptedByteCount
        case .exceedsMaximum:
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product canonical interest state exceeds its byte ceiling",
                codingPath: codingPath
            )
        }

        switch self {
        case .fileMetadata(let interests, let pathScope):
            try Self.validateFileStateMembers(
                interests: interests,
                pathScope: pathScope,
                codingPath: codingPath
            )
        case .reviewMetadata(let interests):
            try Self.validateReviewStateMembers(interests: interests, codingPath: codingPath)
        }
        return canonicalByteCount
    }

    private var flattenedInterests: [(keyBytes: Data, laneTag: UInt8)] {
        switch self {
        case .fileMetadata(let interests, _):
            interests.flatMap { interest in
                interest.paths.map { (Data($0.utf8), Self.laneTag(for: interest.lane)) }
            }
        case .reviewMetadata(let interests):
            interests.flatMap { interest in
                interest.itemIds.map { (Data($0.utf8), Self.laneTag(for: interest.lane)) }
            }
        }
    }

    private var subscriptionKindTag: UInt8 {
        switch self {
        case .fileMetadata: 2
        case .reviewMetadata: 1
        }
    }

    private static func laneTag(for lane: BridgeProductDemandLane) -> UInt8 {
        switch lane {
        case .foreground: 1
        case .active: 2
        case .visible: 3
        case .nearby: 4
        case .speculative: 5
        case .idle: 6
        }
    }

    private static func validateFileStateCounts(
        interests: [BridgeProductFileMetadataInterestStateGroup],
        pathScope: [String],
        codingPath: [any CodingKey]
    ) throws {
        try validateGroupCount(interests.count, codingPath: codingPath)
        try validateMemberCount(
            interests.reduce(0) { $0 + $1.paths.count },
            codingPath: codingPath
        )
        try validateMemberCount(pathScope.count, codingPath: codingPath)
    }

    private static func validateReviewStateCounts(
        interests: [BridgeProductReviewMetadataInterestStateGroup],
        codingPath: [any CodingKey]
    ) throws {
        try validateGroupCount(interests.count, codingPath: codingPath)
        try validateMemberCount(
            interests.reduce(0) { $0 + $1.itemIds.count },
            codingPath: codingPath
        )
    }

    private static func validateFileStateMembers(
        interests: [BridgeProductFileMetadataInterestStateGroup],
        pathScope: [String],
        codingPath: [any CodingKey]
    ) throws {
        var interestPathIdentities = Set<Data>()
        for interest in interests {
            for path in interest.paths {
                try BridgeProductContractDecoding.validateDisplayPath(path, codingPath: codingPath)
                guard interestPathIdentities.insert(Data(path.utf8)).inserted else {
                    throw duplicateStateMemberError(codingPath: codingPath)
                }
            }
        }
        var scopedPathIdentities = Set<Data>()
        for path in pathScope {
            try BridgeProductContractDecoding.validateDisplayPath(path, codingPath: codingPath)
            guard scopedPathIdentities.insert(Data(path.utf8)).inserted else {
                throw duplicateStateMemberError(codingPath: codingPath)
            }
        }
    }

    private static func validateReviewStateMembers(
        interests: [BridgeProductReviewMetadataInterestStateGroup],
        codingPath: [any CodingKey]
    ) throws {
        var itemIdIdentities = Set<Data>()
        for interest in interests {
            for itemId in interest.itemIds {
                try BridgeProductReviewInterestIdentity.validate(itemId, codingPath: codingPath)
                guard itemIdIdentities.insert(Data(itemId.utf8)).inserted else {
                    throw duplicateStateMemberError(codingPath: codingPath)
                }
            }
        }
    }

    private static func validateGroupCount(_ count: Int, codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validateCollectionCount(
            count,
            maximum: BridgeProductWireContract.maximumSubscriptionInterestCount,
            name: "subscription interest-state groups",
            codingPath: codingPath
        )
    }

    private static func validateMemberCount(
        _ count: Int,
        codingPath: [any CodingKey]
    ) throws {
        try BridgeProductContractDecoding.validateCollectionCount(
            count,
            maximum: BridgeProductWireContract.maximumSubscriptionInterestItemCount,
            name: "subscription interest-state members",
            codingPath: codingPath
        )
    }

    private static func duplicateStateMemberError(
        codingPath: [any CodingKey]
    ) -> DecodingError {
        BridgeProductContractDecoding.invalidValue(
            "Subscription interest-state members must be unique",
            codingPath: codingPath
        )
    }
}

extension Data {
    fileprivate mutating func appendLengthPrefixed(_ value: Data) throws {
        try appendUInt32BigEndian(value.count)
        append(value)
    }

    fileprivate mutating func appendUInt32BigEndian(_ value: Int) throws {
        guard let encodedValue = UInt32(exactly: value) else {
            throw BridgeProductContractDecoding.invalidValue(
                "Subscription interest-state count exceeds u32",
                codingPath: []
            )
        }
        append(UInt8((encodedValue >> 24) & 0xff))
        append(UInt8((encodedValue >> 16) & 0xff))
        append(UInt8((encodedValue >> 8) & 0xff))
        append(UInt8(encodedValue & 0xff))
    }
}
