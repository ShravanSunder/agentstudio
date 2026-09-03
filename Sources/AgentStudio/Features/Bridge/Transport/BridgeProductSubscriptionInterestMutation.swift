import Foundation

struct BridgeProductSubscriptionExactUTF8Identity: Hashable, Sendable {
    let bytes: Data

    init(_ value: String) {
        self.bytes = Data(value.utf8)
    }
}

enum BridgeProductSubscriptionInterestMutation {
    static func memberIdentities(in delta: BridgeProductSubscriptionInterestDelta) -> Set<Data> {
        let registration = try! BridgeProductMetadataApplicationRegistry.product.registration(
            for: delta.subscriptionKind
        )
        let erasedDelta = try! registration.decodeInterestDelta(
            from: JSONEncoder.bridgeProductSorted.encode(delta)
        )
        return try! registration.deltaMemberIdentities(erasedDelta)
    }

    static func memberIdentityBytes(
        in delta: BridgeProductSubscriptionInterestDelta
    ) -> Set<Data> {
        memberIdentities(in: delta)
    }

    static func apply(
        _ deltas: [BridgeProductSubscriptionInterestDelta],
        to state: BridgeProductSubscriptionInterestState,
        subscriptionKind: BridgeProductSubscriptionKind
    ) throws -> BridgeProductSubscriptionInterestState {
        guard state.subscriptionKind == subscriptionKind,
            deltas.allSatisfy({ $0.subscriptionKind == subscriptionKind })
        else {
            throw BridgeProductSubscriptionStateError.subscriptionKindMismatch
        }
        let registration = try BridgeProductMetadataApplicationRegistry.product.registration(for: subscriptionKind)
        let erasedDeltas = try deltas.map {
            try registration.decodeInterestDelta(from: JSONEncoder.bridgeProductSorted.encode($0))
        }
        let updatedState = try registration.applying(erasedDeltas, to: state.applicationState)
        return BridgeProductSubscriptionInterestState(
            subscriptionKind: subscriptionKind,
            applicationState: updatedState
        )
    }
}
