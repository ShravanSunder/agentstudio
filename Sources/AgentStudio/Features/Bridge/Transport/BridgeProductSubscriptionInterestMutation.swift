import Foundation

struct BridgeProductSubscriptionExactUTF8Identity: Hashable, Sendable {
    let bytes: Data

    init(_ value: String) {
        self.bytes = Data(value.utf8)
    }
}

private enum BridgeProductSubscriptionDeltaMemberClass: UInt8, Hashable, Sendable {
    case reviewInterest
    case fileInterest
    case filePathScope
}

struct BridgeProductSubscriptionDeltaMemberIdentity: Hashable, Sendable {
    fileprivate let memberClass: BridgeProductSubscriptionDeltaMemberClass
    fileprivate let value: BridgeProductSubscriptionExactUTF8Identity
}

enum BridgeProductSubscriptionInterestMutation {
    private struct InterestMember: Sendable {
        let value: String
        let lane: BridgeProductDemandLane
    }

    private static let demandLaneOrder: [BridgeProductDemandLane] = [
        .foreground,
        .active,
        .visible,
        .nearby,
        .speculative,
        .idle,
    ]

    static func memberIdentities(
        in delta: BridgeProductSubscriptionInterestDelta
    ) -> Set<BridgeProductSubscriptionDeltaMemberIdentity> {
        switch delta {
        case .reviewMetadata(let reviewDelta):
            return Set(
                reviewDelta.add.map {
                    BridgeProductSubscriptionDeltaMemberIdentity(
                        memberClass: .reviewInterest,
                        value: .init($0.itemId)
                    )
                }
                    + reviewDelta.removeItemIds.map {
                        BridgeProductSubscriptionDeltaMemberIdentity(
                            memberClass: .reviewInterest,
                            value: .init($0)
                        )
                    }
            )
        case .fileMetadata(let fileDelta):
            return Set(
                fileDelta.add.map {
                    BridgeProductSubscriptionDeltaMemberIdentity(
                        memberClass: .fileInterest,
                        value: .init($0.path)
                    )
                }
                    + fileDelta.removePaths.map {
                        BridgeProductSubscriptionDeltaMemberIdentity(
                            memberClass: .fileInterest,
                            value: .init($0)
                        )
                    }
                    + fileDelta.addPathScope.map {
                        BridgeProductSubscriptionDeltaMemberIdentity(
                            memberClass: .filePathScope,
                            value: .init($0)
                        )
                    }
                    + fileDelta.removePathScope.map {
                        BridgeProductSubscriptionDeltaMemberIdentity(
                            memberClass: .filePathScope,
                            value: .init($0)
                        )
                    }
            )
        }
    }

    static func apply(
        _ deltas: [BridgeProductSubscriptionInterestDelta],
        to state: BridgeProductSubscriptionInterestState,
        subscriptionKind: BridgeProductSubscriptionKind
    ) throws -> BridgeProductSubscriptionInterestState {
        switch (state, subscriptionKind) {
        case (.reviewMetadata(let groups), .reviewMetadata):
            var members = interestMembers(from: groups)
            for delta in deltas {
                guard case .reviewMetadata(let reviewDelta) = delta else {
                    throw BridgeProductSubscriptionStateError.subscriptionKindMismatch
                }
                for addition in reviewDelta.add {
                    members[.init(addition.itemId)] = InterestMember(
                        value: addition.itemId,
                        lane: addition.lane
                    )
                }
                for itemId in reviewDelta.removeItemIds {
                    members.removeValue(forKey: .init(itemId))
                }
            }
            return .reviewMetadata(interests: try reviewGroups(from: members))

        case (.fileMetadata(let groups, let pathScope), .fileMetadata):
            var members = interestMembers(from: groups)
            var scopedPaths = Dictionary(
                uniqueKeysWithValues: pathScope.map {
                    (BridgeProductSubscriptionExactUTF8Identity($0), $0)
                }
            )
            for delta in deltas {
                guard case .fileMetadata(let fileDelta) = delta else {
                    throw BridgeProductSubscriptionStateError.subscriptionKindMismatch
                }
                for addition in fileDelta.add {
                    members[.init(addition.path)] = InterestMember(
                        value: addition.path,
                        lane: addition.lane
                    )
                }
                for path in fileDelta.removePaths {
                    members.removeValue(forKey: .init(path))
                }
                for path in fileDelta.addPathScope {
                    scopedPaths[.init(path)] = path
                }
                for path in fileDelta.removePathScope {
                    scopedPaths.removeValue(forKey: .init(path))
                }
            }
            let orderedPathScope =
                scopedPaths
                .map { (identity: $0.key, path: $0.value) }
                .sorted { $0.identity.bytes.lexicographicallyPrecedes($1.identity.bytes) }
                .map(\.path)
            return .fileMetadata(
                interests: try fileGroups(from: members),
                pathScope: orderedPathScope
            )

        default:
            throw BridgeProductSubscriptionStateError.subscriptionKindMismatch
        }
    }

    private static func interestMembers(
        from groups: [BridgeProductReviewMetadataInterestStateGroup]
    ) -> [BridgeProductSubscriptionExactUTF8Identity: InterestMember] {
        Dictionary(
            uniqueKeysWithValues: groups.flatMap { group in
                group.itemIds.map {
                    (BridgeProductSubscriptionExactUTF8Identity($0), InterestMember(value: $0, lane: group.lane))
                }
            }
        )
    }

    private static func interestMembers(
        from groups: [BridgeProductFileMetadataInterestStateGroup]
    ) -> [BridgeProductSubscriptionExactUTF8Identity: InterestMember] {
        Dictionary(
            uniqueKeysWithValues: groups.flatMap { group in
                group.paths.map {
                    (BridgeProductSubscriptionExactUTF8Identity($0), InterestMember(value: $0, lane: group.lane))
                }
            }
        )
    }

    private static func reviewGroups(
        from members: [BridgeProductSubscriptionExactUTF8Identity: InterestMember]
    ) throws -> [BridgeProductReviewMetadataInterestStateGroup] {
        try demandLaneOrder.compactMap { lane in
            let values = orderedValues(in: members, lane: lane)
            guard !values.isEmpty else { return nil }
            return try BridgeProductReviewMetadataInterestStateGroup(itemIds: values, lane: lane)
        }
    }

    private static func fileGroups(
        from members: [BridgeProductSubscriptionExactUTF8Identity: InterestMember]
    ) throws -> [BridgeProductFileMetadataInterestStateGroup] {
        try demandLaneOrder.compactMap { lane in
            let values = orderedValues(in: members, lane: lane)
            guard !values.isEmpty else { return nil }
            return try BridgeProductFileMetadataInterestStateGroup(lane: lane, paths: values)
        }
    }

    private static func orderedValues(
        in members: [BridgeProductSubscriptionExactUTF8Identity: InterestMember],
        lane: BridgeProductDemandLane
    ) -> [String] {
        members
            .filter { $0.value.lane == lane }
            .map { (identity: $0.key, value: $0.value.value) }
            .sorted { $0.identity.bytes.lexicographicallyPrecedes($1.identity.bytes) }
            .map(\.value)
    }
}
