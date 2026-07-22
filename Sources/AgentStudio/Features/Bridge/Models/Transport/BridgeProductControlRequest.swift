import Foundation

private typealias BridgeProductPaneControlRequestIdentity = BridgeProductControlCorrelation
private typealias BridgeProductSurfaceControlRequestIdentity = BridgeProductSurfaceRequestIdentity

enum BridgeProductControlRequest: Codable, Equatable, Sendable {
    case workerSessionOpen(BridgeProductWorkerSessionOpenRequest)
    case productCall(BridgeProductCallControlRequest)
    case subscriptionOpen(BridgeProductSubscriptionOpenRequest)
    case subscriptionUpdateBatch(BridgeProductSubscriptionUpdateBatchRequest)
    case subscriptionCancel(BridgeProductSubscriptionCancelRequest)
    case workerSessionResync(BridgeProductWorkerSessionResyncRequest)

    private enum CodingKeys: String, CodingKey {
        case kind
    }

    var kind: String {
        switch self {
        case .workerSessionOpen: "workerSession.open"
        case .productCall: "product.call"
        case .subscriptionOpen: "subscription.open"
        case .subscriptionUpdateBatch: "subscription.updateBatch"
        case .subscriptionCancel: "subscription.cancel"
        case .workerSessionResync: "workerSession.resync"
        }
    }

    var correlation: BridgeProductControlCorrelation {
        switch self {
        case .workerSessionOpen(let request): request.correlation
        case .productCall(let request): request.correlation
        case .subscriptionOpen(let request): request.correlation
        case .subscriptionUpdateBatch(let request): request.correlation
        case .subscriptionCancel(let request): request.correlation
        case .workerSessionResync(let request): request.correlation
        }
    }

    var paneSessionId: String { correlation.paneSessionId }
    var requestId: String { correlation.requestId }
    var requestSequence: Int { correlation.requestSequence }
    var workerInstanceId: String { correlation.workerInstanceId }

    var surface: BridgeProductSurface? {
        switch self {
        case .workerSessionOpen, .workerSessionResync:
            nil
        case .productCall(let request):
            request.surface
        case .subscriptionOpen(let request):
            request.surface
        case .subscriptionUpdateBatch(let request):
            request.surface
        case .subscriptionCancel(let request):
            request.surface
        }
    }

    var workerDerivationEpoch: Int? {
        switch self {
        case .workerSessionOpen, .workerSessionResync:
            nil
        case .productCall(let request):
            request.workerDerivationEpoch
        case .subscriptionOpen(let request):
            request.workerDerivationEpoch
        case .subscriptionUpdateBatch(let request):
            request.workerDerivationEpoch
        case .subscriptionCancel(let request):
            request.workerDerivationEpoch
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "workerSession.open":
            self = .workerSessionOpen(try BridgeProductWorkerSessionOpenRequest(from: decoder))
        case "product.call":
            self = .productCall(try BridgeProductCallControlRequest(from: decoder))
        case "subscription.open":
            self = .subscriptionOpen(try BridgeProductSubscriptionOpenRequest(from: decoder))
        case "subscription.updateBatch":
            self = .subscriptionUpdateBatch(try BridgeProductSubscriptionUpdateBatchRequest(from: decoder))
        case "subscription.cancel":
            self = .subscriptionCancel(try BridgeProductSubscriptionCancelRequest(from: decoder))
        case "workerSession.resync":
            self = .workerSessionResync(try BridgeProductWorkerSessionResyncRequest(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown Bridge product control request kind"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .workerSessionOpen(let request): try request.encode(to: encoder)
        case .productCall(let request): try request.encode(to: encoder)
        case .subscriptionOpen(let request): try request.encode(to: encoder)
        case .subscriptionUpdateBatch(let request): try request.encode(to: encoder)
        case .subscriptionCancel(let request): try request.encode(to: encoder)
        case .workerSessionResync(let request): try request.encode(to: encoder)
        }
    }
}

struct BridgeProductWorkerSessionOpenRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case request
    }

    private let identity: BridgeProductPaneControlRequestIdentity

    var correlation: BridgeProductControlCorrelation { identity }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductPaneControlRequestIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "workerSession.open request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "workerSession.open" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid workerSession.open request kind",
                codingPath: decoder.codingPath
            )
        }
        try BridgeProductContractDecoding.decodeRequiredNull(
            forKey: .request,
            from: container,
            codingPath: decoder.codingPath
        )
        self.identity = try BridgeProductPaneControlRequestIdentity(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("workerSession.open", forKey: .kind)
        try container.encodeNil(forKey: .request)
    }
}

struct BridgeProductCallControlRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case call
        case kind
    }

    private let identity: BridgeProductSurfaceControlRequestIdentity
    let call: BridgeProductCallRequest

    var correlation: BridgeProductControlCorrelation { identity.correlation }
    var surface: BridgeProductSurface { call.surface }
    var workerDerivationEpoch: Int { identity.workerDerivationEpoch }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductSurfaceControlRequestIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "product.call request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.call = try container.decode(BridgeProductCallRequest.self, forKey: .call)
        guard try container.decode(String.self, forKey: .kind) == "product.call" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid product.call request kind",
                codingPath: decoder.codingPath
            )
        }
        self.identity = try BridgeProductSurfaceControlRequestIdentity(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(call, forKey: .call)
        try container.encode("product.call", forKey: .kind)
    }
}

struct BridgeProductSubscriptionOpenRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case subscription
        case subscriptionId
    }

    private let identity: BridgeProductSurfaceControlRequestIdentity
    let subscription: BridgeProductSubscriptionRequest
    let subscriptionId: String

    var correlation: BridgeProductControlCorrelation { identity.correlation }
    var surface: BridgeProductSurface { subscription.surface }
    var workerDerivationEpoch: Int { identity.workerDerivationEpoch }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductSurfaceControlRequestIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "subscription.open request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "subscription.open" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid subscription.open request kind",
                codingPath: decoder.codingPath
            )
        }
        self.subscription = try container.decode(BridgeProductSubscriptionRequest.self, forKey: .subscription)
        self.subscriptionId = try container.decode(String.self, forKey: .subscriptionId)
        self.identity = try BridgeProductSurfaceControlRequestIdentity(from: decoder)
        try BridgeProductContractDecoding.validateIdentifier(subscriptionId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("subscription.open", forKey: .kind)
        try container.encode(subscription, forKey: .subscription)
        try container.encode(subscriptionId, forKey: .subscriptionId)
    }
}

struct BridgeProductSubscriptionUpdateBatchRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case baseInterestRevision
        case baseInterestSha256
        case batchCount
        case batchIndex
        case delta
        case kind
        case subscriptionId
        case subscriptionKind
        case targetInterestRevision
        case targetInterestSha256
        case totalDeltaItemCount
        case updateId
    }

    private let identity: BridgeProductSurfaceControlRequestIdentity
    let baseInterestRevision: Int
    let baseInterestSha256: String
    let batchCount: Int
    let batchIndex: Int
    let delta: BridgeProductSubscriptionInterestDelta
    let subscriptionId: String
    let subscriptionKind: BridgeProductSubscriptionKind
    let targetInterestRevision: Int
    let targetInterestSha256: String
    let totalDeltaItemCount: Int
    let updateId: String

    var correlation: BridgeProductControlCorrelation { identity.correlation }
    var surface: BridgeProductSurface { subscriptionKind.surface }
    var workerDerivationEpoch: Int { identity.workerDerivationEpoch }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductSurfaceControlRequestIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "subscription.updateBatch request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.baseInterestRevision = try container.decode(Int.self, forKey: .baseInterestRevision)
        self.baseInterestSha256 = try container.decode(String.self, forKey: .baseInterestSha256)
        self.batchCount = try container.decode(Int.self, forKey: .batchCount)
        self.batchIndex = try container.decode(Int.self, forKey: .batchIndex)
        self.delta = try container.decode(BridgeProductSubscriptionInterestDelta.self, forKey: .delta)
        guard try container.decode(String.self, forKey: .kind) == "subscription.updateBatch" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid subscription.updateBatch request kind",
                codingPath: decoder.codingPath
            )
        }
        self.subscriptionId = try container.decode(String.self, forKey: .subscriptionId)
        self.subscriptionKind = try container.decode(
            BridgeProductSubscriptionKind.self,
            forKey: .subscriptionKind
        )
        self.targetInterestRevision = try container.decode(Int.self, forKey: .targetInterestRevision)
        self.targetInterestSha256 = try container.decode(String.self, forKey: .targetInterestSha256)
        self.totalDeltaItemCount = try container.decode(Int.self, forKey: .totalDeltaItemCount)
        self.updateId = try container.decode(String.self, forKey: .updateId)
        self.identity = try BridgeProductSurfaceControlRequestIdentity(from: decoder)

        try BridgeProductContractDecoding.validateNonnegative(
            baseInterestRevision,
            name: "baseInterestRevision",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateSHA256(baseInterestSha256, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validatePositive(
            batchCount,
            name: "batchCount",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            batchCount,
            maximum: BridgeProductWireContract.maximumSubscriptionDeltaItemCount,
            name: "batchCount",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateNonnegative(
            batchIndex,
            name: "batchIndex",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(subscriptionId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validatePositive(
            targetInterestRevision,
            name: "targetInterestRevision",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateSHA256(targetInterestSha256, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validatePositive(
            totalDeltaItemCount,
            name: "totalDeltaItemCount",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            totalDeltaItemCount,
            maximum: BridgeProductWireContract.maximumSubscriptionDeltaItemCount,
            name: "totalDeltaItemCount",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(updateId, codingPath: decoder.codingPath)
        guard subscriptionKind == delta.subscriptionKind else {
            throw BridgeProductContractDecoding.invalidValue(
                "Subscription update kind must match its typed interest delta",
                codingPath: decoder.codingPath
            )
        }
        guard targetInterestRevision == baseInterestRevision + 1 else {
            throw BridgeProductContractDecoding.invalidValue(
                "Subscription update must advance exactly one interest revision",
                codingPath: decoder.codingPath
            )
        }
        guard batchIndex < batchCount else {
            throw BridgeProductContractDecoding.invalidValue(
                "Subscription update batch index must be below its batch count",
                codingPath: decoder.codingPath
            )
        }
        guard delta.itemCount > 0, delta.itemCount <= totalDeltaItemCount else {
            throw BridgeProductContractDecoding.invalidValue(
                "Subscription update batch item count must fit its declared total",
                codingPath: decoder.codingPath
            )
        }
        guard batchCount <= totalDeltaItemCount else {
            throw BridgeProductContractDecoding.invalidValue(
                "Subscription update cannot declare more nonempty batches than items",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(baseInterestRevision, forKey: .baseInterestRevision)
        try container.encode(baseInterestSha256, forKey: .baseInterestSha256)
        try container.encode(batchCount, forKey: .batchCount)
        try container.encode(batchIndex, forKey: .batchIndex)
        try container.encode(delta, forKey: .delta)
        try container.encode("subscription.updateBatch", forKey: .kind)
        try container.encode(subscriptionId, forKey: .subscriptionId)
        try container.encode(subscriptionKind, forKey: .subscriptionKind)
        try container.encode(targetInterestRevision, forKey: .targetInterestRevision)
        try container.encode(targetInterestSha256, forKey: .targetInterestSha256)
        try container.encode(totalDeltaItemCount, forKey: .totalDeltaItemCount)
        try container.encode(updateId, forKey: .updateId)
    }
}

struct BridgeProductSubscriptionCancelRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case subscriptionId
        case subscriptionKind
    }

    private let identity: BridgeProductSurfaceControlRequestIdentity
    let subscriptionId: String
    let subscriptionKind: BridgeProductSubscriptionKind

    var correlation: BridgeProductControlCorrelation { identity.correlation }
    var surface: BridgeProductSurface { subscriptionKind.surface }
    var workerDerivationEpoch: Int { identity.workerDerivationEpoch }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductSurfaceControlRequestIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "subscription.cancel request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "subscription.cancel" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid subscription.cancel request kind",
                codingPath: decoder.codingPath
            )
        }
        self.subscriptionId = try container.decode(String.self, forKey: .subscriptionId)
        self.subscriptionKind = try container.decode(BridgeProductSubscriptionKind.self, forKey: .subscriptionKind)
        self.identity = try BridgeProductSurfaceControlRequestIdentity(from: decoder)
        try BridgeProductContractDecoding.validateIdentifier(subscriptionId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("subscription.cancel", forKey: .kind)
        try container.encode(subscriptionId, forKey: .subscriptionId)
        try container.encode(subscriptionKind, forKey: .subscriptionKind)
    }
}

struct BridgeProductActiveSubscription: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case interestRevision
        case interestSha256
        case subscriptionId
        case subscriptionKind
        case workerDerivationEpoch
    }

    let interestRevision: Int
    let interestSha256: String
    let subscriptionId: String
    let subscriptionKind: BridgeProductSubscriptionKind
    let workerDerivationEpoch: Int

    var surface: BridgeProductSurface { subscriptionKind.surface }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "active Bridge product subscription"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.interestRevision = try container.decode(Int.self, forKey: .interestRevision)
        self.interestSha256 = try container.decode(String.self, forKey: .interestSha256)
        self.subscriptionId = try container.decode(String.self, forKey: .subscriptionId)
        self.subscriptionKind = try container.decode(BridgeProductSubscriptionKind.self, forKey: .subscriptionKind)
        self.workerDerivationEpoch = try container.decode(
            Int.self,
            forKey: .workerDerivationEpoch
        )
        try BridgeProductContractDecoding.validateNonnegative(
            interestRevision,
            name: "interestRevision",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateSHA256(interestSha256, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(subscriptionId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            workerDerivationEpoch,
            name: "workerDerivationEpoch",
            codingPath: decoder.codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(interestRevision, forKey: .interestRevision)
        try container.encode(interestSha256, forKey: .interestSha256)
        try container.encode(subscriptionId, forKey: .subscriptionId)
        try container.encode(subscriptionKind, forKey: .subscriptionKind)
        try container.encode(workerDerivationEpoch, forKey: .workerDerivationEpoch)
    }
}

struct BridgeProductWorkerSessionResyncRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case activeSubscriptions
        case kind
        case lastAcceptedRequestSequence
        case lastAcceptedStreamSequence
    }

    private let identity: BridgeProductPaneControlRequestIdentity
    let activeSubscriptions: [BridgeProductActiveSubscription]
    let lastAcceptedRequestSequence: Int
    let lastAcceptedStreamSequence: Int

    var correlation: BridgeProductControlCorrelation { identity }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductPaneControlRequestIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "workerSession.resync request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.activeSubscriptions = try container.decode(
            [BridgeProductActiveSubscription].self,
            forKey: .activeSubscriptions
        )
        guard try container.decode(String.self, forKey: .kind) == "workerSession.resync" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid workerSession.resync request kind",
                codingPath: decoder.codingPath
            )
        }
        self.lastAcceptedRequestSequence = try container.decode(Int.self, forKey: .lastAcceptedRequestSequence)
        self.lastAcceptedStreamSequence = try container.decode(Int.self, forKey: .lastAcceptedStreamSequence)
        self.identity = try BridgeProductPaneControlRequestIdentity(from: decoder)
        try BridgeProductContractDecoding.validateCollectionCount(
            activeSubscriptions.count,
            maximum: BridgeProductWireContract.maximumActiveSubscriptionCount,
            name: "active subscriptions",
            codingPath: decoder.codingPath
        )
        guard Set(activeSubscriptions.map(\.subscriptionId)).count == activeSubscriptions.count else {
            throw BridgeProductContractDecoding.invalidValue(
                "Duplicate active Bridge product subscription id",
                codingPath: decoder.codingPath
            )
        }
        var workerDerivationEpochBySurface: [BridgeProductSurface: Int] = [:]
        for subscription in activeSubscriptions {
            if let existingEpoch = workerDerivationEpochBySurface[subscription.surface],
                existingEpoch != subscription.workerDerivationEpoch
            {
                throw BridgeProductContractDecoding.invalidValue(
                    "Active subscriptions for one surface must share a derivation epoch",
                    codingPath: decoder.codingPath
                )
            }
            workerDerivationEpochBySurface[subscription.surface] = subscription.workerDerivationEpoch
        }
        try BridgeProductContractDecoding.validateNonnegative(
            lastAcceptedRequestSequence,
            name: "lastAcceptedRequestSequence",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateNonnegative(
            lastAcceptedStreamSequence,
            name: "lastAcceptedStreamSequence",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            lastAcceptedStreamSequence,
            maximum: BridgeProductWireContract.maximumResumableStreamSequence,
            name: "lastAcceptedStreamSequence",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            lastAcceptedRequestSequence,
            maximum: BridgeProductWireContract.maximumControlRequestSequence - 1,
            name: "lastAcceptedRequestSequence",
            codingPath: decoder.codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activeSubscriptions, forKey: .activeSubscriptions)
        try container.encode("workerSession.resync", forKey: .kind)
        try container.encode(lastAcceptedRequestSequence, forKey: .lastAcceptedRequestSequence)
        try container.encode(lastAcceptedStreamSequence, forKey: .lastAcceptedStreamSequence)
    }
}
