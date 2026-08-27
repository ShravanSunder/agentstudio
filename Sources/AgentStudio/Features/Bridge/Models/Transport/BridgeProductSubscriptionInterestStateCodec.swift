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

struct BridgeProductSubscriptionInterestState: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey { case subscriptionKind }

    let subscriptionKind: BridgeProductSubscriptionKind
    let applicationState: BridgeProductMetadataApplicationValue

    init(
        subscriptionKind: BridgeProductSubscriptionKind,
        applicationState: BridgeProductMetadataApplicationValue
    ) {
        self.subscriptionKind = subscriptionKind
        self.applicationState = applicationState
    }

    var fileMetadataState: BridgeProductFileMetadataInterestState? {
        guard subscriptionKind == .fileMetadata else { return nil }
        return try? JSONDecoder().decode(
            BridgeProductFileMetadataInterestState.self,
            from: applicationState.encodedValue
        )
    }

    var reviewMetadataState: BridgeProductReviewMetadataInterestState? {
        guard subscriptionKind == .reviewMetadata else { return nil }
        return try? JSONDecoder().decode(
            BridgeProductReviewMetadataInterestState.self,
            from: applicationState.encodedValue
        )
    }

    init(from decoder: Decoder) throws {
        let rawValue = try BridgeProductJSONValue(from: decoder)
        guard case .object(var members) = rawValue,
            case .string(let rawKind)? = members.removeValue(forKey: CodingKeys.subscriptionKind.rawValue),
            let kind = BridgeProductSubscriptionKind(rawValue: rawKind)
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product interest state requires a valid subscriptionKind",
                codingPath: decoder.codingPath
            )
        }
        let registration = try BridgeProductMetadataApplicationRegistry.product.registration(for: kind)
        let encodedState = try JSONEncoder.bridgeProductSorted.encode(BridgeProductJSONValue.object(members))
        let decodedState = try registration.decodeInterestState(from: encodedState)
        _ = try registration.canonicalInterestBytes(from: decodedState)
        subscriptionKind = kind
        applicationState = decodedState
    }

    func encode(to encoder: Encoder) throws {
        guard
            case .object(var members) = try JSONDecoder().decode(
                BridgeProductJSONValue.self,
                from: applicationState.encodedValue
            )
        else {
            throw BridgeProductMetadataApplicationRegistryError.typeErasureMismatch
        }
        members[CodingKeys.subscriptionKind.rawValue] = .string(subscriptionKind.rawValue)
        try BridgeProductJSONValue.object(members).encode(to: encoder)
    }

    func encodedData() throws -> Data {
        let registration = try BridgeProductMetadataApplicationRegistry.product.registration(for: subscriptionKind)
        return try registration.canonicalInterestBytes(from: applicationState)
    }

    func sha256Hex() throws -> String {
        SHA256.hash(data: try encodedData()).map { String(format: "%02x", $0) }.joined()
    }

    func canonicalEncodingPreflight() -> BridgeProductInterestStateEncodingPreflight {
        let registration = try! BridgeProductMetadataApplicationRegistry.product.registration(for: subscriptionKind)
        return try! registration.canonicalInterestPreflight(applicationState)
    }

    @discardableResult
    func validateForCanonicalEncoding(codingPath _: [any CodingKey] = []) throws -> Int {
        try encodedData().count
    }

    static let fileAnnotations = try! registered(
        kind: .fileAnnotations,
        state: BridgeProductAnnotationInterestState()
    )

    static func fileMetadata(
        interests: [BridgeProductFileMetadataInterestStateGroup],
        pathScope: [String]
    ) -> Self {
        try! registered(
            kind: .fileMetadata,
            state: BridgeProductFileMetadataInterestState(interests: interests, pathScope: pathScope)
        )
    }

    static let reviewAnnotations = try! registered(
        kind: .reviewAnnotations,
        state: BridgeProductAnnotationInterestState()
    )

    static func reviewMetadata(interests: [BridgeProductReviewMetadataInterestStateGroup]) -> Self {
        try! registered(
            kind: .reviewMetadata,
            state: BridgeProductReviewMetadataInterestState(interests: interests)
        )
    }

    private static func registered<TState: Encodable>(
        kind: BridgeProductSubscriptionKind,
        state: TState
    ) throws -> Self {
        Self(
            subscriptionKind: kind,
            applicationState: BridgeProductMetadataApplicationValue(
                applicationKind: kind,
                encodedValue: try JSONEncoder.bridgeProductSorted.encode(state)
            )
        )
    }
}

enum BridgeProductInterestStateCanonicalCodec {
    static func fileMetadataBody(
        interests: [BridgeProductFileMetadataInterestStateGroup],
        pathScope: [String]
    ) throws -> Data {
        try validateFileStateCounts(interests: interests, pathScope: pathScope, codingPath: [])
        try validateFileStateMembers(interests: interests, pathScope: pathScope, codingPath: [])
        let preflight = fileMetadataPreflight(interests: interests, pathScope: pathScope)
        let canonicalByteCount = try acceptedByteCount(preflight, codingPath: [])
        return try encodeBody(
            canonicalByteCount: canonicalByteCount - 2,
            flattenedInterests: interests.flatMap { interest in
                interest.paths.map { (Data($0.utf8), laneTag(for: interest.lane)) }
            },
            pathScope: pathScope
        )
    }

    static func reviewMetadataBody(
        interests: [BridgeProductReviewMetadataInterestStateGroup]
    ) throws -> Data {
        try validateReviewStateCounts(interests: interests, codingPath: [])
        try validateReviewStateMembers(interests: interests, codingPath: [])
        let preflight = reviewMetadataPreflight(interests: interests)
        let canonicalByteCount = try acceptedByteCount(preflight, codingPath: [])
        return try encodeBody(
            canonicalByteCount: canonicalByteCount - 2,
            flattenedInterests: interests.flatMap { interest in
                interest.itemIds.map { (Data($0.utf8), laneTag(for: interest.lane)) }
            },
            pathScope: nil
        )
    }

    static func fileMetadataPreflight(
        interests: [BridgeProductFileMetadataInterestStateGroup],
        pathScope: [String]
    ) -> BridgeProductInterestStateEncodingPreflight {
        preflight(initialByteCount: 10, interestValues: interests.flatMap(\.paths), pathScope: pathScope)
    }

    static func reviewMetadataPreflight(
        interests: [BridgeProductReviewMetadataInterestStateGroup]
    ) -> BridgeProductInterestStateEncodingPreflight {
        preflight(initialByteCount: 6, interestValues: interests.flatMap(\.itemIds), pathScope: [])
    }

    private static func preflight(
        initialByteCount: Int,
        interestValues: [String],
        pathScope: [String]
    ) -> BridgeProductInterestStateEncodingPreflight {
        var canonicalByteCount = initialByteCount
        var visitedTextValueCount = 0
        for (value, overhead) in interestValues.map({ ($0, 5) }) + pathScope.map({ ($0, 4) }) {
            canonicalByteCount += overhead + value.utf8.count
            visitedTextValueCount += 1
            if canonicalByteCount > BridgeProductWireContract.maximumSubscriptionInterestStateBytes {
                return .exceedsMaximum(
                    canonicalByteCountLowerBound: canonicalByteCount,
                    maximumCanonicalByteCount: BridgeProductWireContract.maximumSubscriptionInterestStateBytes,
                    visitedTextValueCount: visitedTextValueCount
                )
            }
        }
        return .accepted(
            canonicalByteCount: canonicalByteCount,
            visitedTextValueCount: visitedTextValueCount
        )
    }

    private static func encodeBody(
        canonicalByteCount: Int,
        flattenedInterests: [(Data, UInt8)],
        pathScope: [String]?
    ) throws -> Data {
        var encoded = Data(capacity: canonicalByteCount)
        let sortedInterests = flattenedInterests.sorted { $0.0.lexicographicallyPrecedes($1.0) }
        try encoded.appendUInt32BigEndian(sortedInterests.count)
        for (keyBytes, laneTag) in sortedInterests {
            try encoded.appendLengthPrefixed(keyBytes)
            encoded.append(laneTag)
        }
        if let pathScope {
            let sortedScope = pathScope.map { Data($0.utf8) }.sorted { $0.lexicographicallyPrecedes($1) }
            try encoded.appendUInt32BigEndian(sortedScope.count)
            for pathBytes in sortedScope {
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

    private static func acceptedByteCount(
        _ preflight: BridgeProductInterestStateEncodingPreflight,
        codingPath: [any CodingKey]
    ) throws -> Int {
        guard case .accepted(let byteCount, _) = preflight else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product canonical interest state exceeds its byte ceiling",
                codingPath: codingPath
            )
        }
        return byteCount
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
