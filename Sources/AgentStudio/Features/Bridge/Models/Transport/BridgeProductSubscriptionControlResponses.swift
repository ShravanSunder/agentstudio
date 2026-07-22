import Foundation

enum BridgeProductSubscriptionUpdateBatchDisposition: String, Codable, Equatable, Sendable {
    case staged
    case committed
}

struct BridgeProductSubscriptionOpenAcceptedResponse: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case interestRevision
        case interestSha256
        case kind
        case subscriptionId
        case subscriptionKind
    }

    private let identity: BridgeProductControlCorrelation
    let interestRevision: Int
    let interestSha256: String
    let subscriptionId: String
    let subscriptionKind: BridgeProductSubscriptionKind

    var correlation: BridgeProductControlCorrelation { identity }

    init(
        correlation: BridgeProductControlCorrelation,
        interestSha256: String,
        subscriptionId: String,
        subscriptionKind: BridgeProductSubscriptionKind
    ) throws {
        try BridgeProductContractDecoding.validateSHA256(interestSha256, codingPath: [])
        try BridgeProductContractDecoding.validateIdentifier(subscriptionId, codingPath: [])
        self.identity = correlation
        self.interestRevision = 0
        self.interestSha256 = interestSha256
        self.subscriptionId = subscriptionId
        self.subscriptionKind = subscriptionKind
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductControlCorrelation.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "subscription.openAccepted response"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.interestRevision = try container.decode(Int.self, forKey: .interestRevision)
        self.interestSha256 = try container.decode(String.self, forKey: .interestSha256)
        guard try container.decode(String.self, forKey: .kind) == "subscription.openAccepted" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid subscription.openAccepted response kind",
                codingPath: decoder.codingPath
            )
        }
        self.subscriptionId = try container.decode(String.self, forKey: .subscriptionId)
        self.subscriptionKind = try container.decode(
            BridgeProductSubscriptionKind.self,
            forKey: .subscriptionKind
        )
        self.identity = try BridgeProductControlCorrelation(from: decoder)
        guard interestRevision == 0 else {
            throw BridgeProductContractDecoding.invalidValue(
                "subscription.openAccepted interest revision must be zero",
                codingPath: decoder.codingPath
            )
        }
        try BridgeProductContractDecoding.validateSHA256(interestSha256, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(subscriptionId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(interestRevision, forKey: .interestRevision)
        try container.encode(interestSha256, forKey: .interestSha256)
        try container.encode("subscription.openAccepted", forKey: .kind)
        try container.encode(subscriptionId, forKey: .subscriptionId)
        try container.encode(subscriptionKind, forKey: .subscriptionKind)
    }
}

struct BridgeProductSubscriptionBatchAcceptedResponse: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case batchIndex
        case disposition
        case kind
        case subscriptionId
        case subscriptionKind
        case targetInterestRevision
        case targetInterestSha256
        case updateId
    }

    private let identity: BridgeProductControlCorrelation
    let batchIndex: Int
    let disposition: BridgeProductSubscriptionUpdateBatchDisposition
    let subscriptionId: String
    let subscriptionKind: BridgeProductSubscriptionKind
    let targetInterestRevision: Int
    let targetInterestSha256: String
    let updateId: String

    var correlation: BridgeProductControlCorrelation { identity }

    init(
        batchIndex: Int,
        correlation: BridgeProductControlCorrelation,
        disposition: BridgeProductSubscriptionUpdateBatchDisposition,
        subscriptionId: String,
        subscriptionKind: BridgeProductSubscriptionKind,
        targetInterestRevision: Int,
        targetInterestSha256: String,
        updateId: String
    ) throws {
        try Self.validate(
            batchIndex: batchIndex,
            subscriptionId: subscriptionId,
            targetInterestRevision: targetInterestRevision,
            targetInterestSha256: targetInterestSha256,
            updateId: updateId,
            codingPath: []
        )
        self.identity = correlation
        self.batchIndex = batchIndex
        self.disposition = disposition
        self.subscriptionId = subscriptionId
        self.subscriptionKind = subscriptionKind
        self.targetInterestRevision = targetInterestRevision
        self.targetInterestSha256 = targetInterestSha256
        self.updateId = updateId
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductControlCorrelation.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "subscription.updateBatchAccepted response"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.batchIndex = try container.decode(Int.self, forKey: .batchIndex)
        self.disposition = try container.decode(
            BridgeProductSubscriptionUpdateBatchDisposition.self,
            forKey: .disposition
        )
        guard try container.decode(String.self, forKey: .kind) == "subscription.updateBatchAccepted" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid subscription.updateBatchAccepted response kind",
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
        self.updateId = try container.decode(String.self, forKey: .updateId)
        self.identity = try BridgeProductControlCorrelation(from: decoder)
        try Self.validate(
            batchIndex: batchIndex,
            subscriptionId: subscriptionId,
            targetInterestRevision: targetInterestRevision,
            targetInterestSha256: targetInterestSha256,
            updateId: updateId,
            codingPath: decoder.codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(batchIndex, forKey: .batchIndex)
        try container.encode(disposition, forKey: .disposition)
        try container.encode("subscription.updateBatchAccepted", forKey: .kind)
        try container.encode(subscriptionId, forKey: .subscriptionId)
        try container.encode(subscriptionKind, forKey: .subscriptionKind)
        try container.encode(targetInterestRevision, forKey: .targetInterestRevision)
        try container.encode(targetInterestSha256, forKey: .targetInterestSha256)
        try container.encode(updateId, forKey: .updateId)
    }

    private static func validate(
        batchIndex: Int,
        subscriptionId: String,
        targetInterestRevision: Int,
        targetInterestSha256: String,
        updateId: String,
        codingPath: [any CodingKey]
    ) throws {
        try BridgeProductContractDecoding.validateNonnegative(
            batchIndex,
            name: "batchIndex",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(subscriptionId, codingPath: codingPath)
        try BridgeProductContractDecoding.validatePositive(
            targetInterestRevision,
            name: "targetInterestRevision",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateSHA256(targetInterestSha256, codingPath: codingPath)
        try BridgeProductContractDecoding.validateIdentifier(updateId, codingPath: codingPath)
    }
}

struct BridgeProductSubscriptionCancelAcceptedResponse: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case subscriptionId
        case subscriptionKind
    }

    private let identity: BridgeProductControlCorrelation
    let subscriptionId: String
    let subscriptionKind: BridgeProductSubscriptionKind

    var correlation: BridgeProductControlCorrelation { identity }

    init(
        correlation: BridgeProductControlCorrelation,
        subscriptionId: String,
        subscriptionKind: BridgeProductSubscriptionKind
    ) {
        self.identity = correlation
        self.subscriptionId = subscriptionId
        self.subscriptionKind = subscriptionKind
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductControlCorrelation.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "subscription.cancelAccepted response"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "subscription.cancelAccepted" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid subscription.cancelAccepted response kind",
                codingPath: decoder.codingPath
            )
        }
        self.subscriptionId = try container.decode(String.self, forKey: .subscriptionId)
        self.subscriptionKind = try container.decode(
            BridgeProductSubscriptionKind.self,
            forKey: .subscriptionKind
        )
        self.identity = try BridgeProductControlCorrelation(from: decoder)
        try BridgeProductContractDecoding.validateIdentifier(subscriptionId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("subscription.cancelAccepted", forKey: .kind)
        try container.encode(subscriptionId, forKey: .subscriptionId)
        try container.encode(subscriptionKind, forKey: .subscriptionKind)
    }
}
