import Foundation

enum BridgeProductViewScopeContract {
    static func validate(_ scope: BridgeProductJSONValue, codingPath: [any CodingKey]) throws {
        guard case .object(let members) = scope,
            case .string(let kind)? = members["kind"]
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "View scope requires an object kind",
                codingPath: codingPath
            )
        }
        try BridgeProductContractDecoding.validateNonemptyString(kind, codingPath: codingPath)
    }
}

struct BridgeProductViewScopeRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case handle
        case kind
        case scope
        case scopeRevision
        case subscriptionId
        case subscriptionKind
    }

    let correlation: BridgeProductControlCorrelation
    let handle: String
    let scope: BridgeProductJSONValue
    let scopeRevision: Int
    let subscriptionId: String
    let subscriptionKind: BridgeProductSubscriptionKind

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductControlCorrelation.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "subscription.setScope request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "subscription.setScope" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid subscription.setScope request kind",
                codingPath: decoder.codingPath
            )
        }
        correlation = try BridgeProductControlCorrelation(from: decoder)
        handle = try container.decode(String.self, forKey: .handle)
        scope = try container.decode(BridgeProductJSONValue.self, forKey: .scope)
        try BridgeProductViewScopeContract.validate(scope, codingPath: decoder.codingPath)
        scopeRevision = try container.decode(Int.self, forKey: .scopeRevision)
        subscriptionId = try container.decode(String.self, forKey: .subscriptionId)
        subscriptionKind = try container.decode(BridgeProductSubscriptionKind.self, forKey: .subscriptionKind)
        try BridgeProductContractDecoding.validateIdentifier(handle, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            scopeRevision,
            name: "scopeRevision",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(subscriptionId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try correlation.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(handle, forKey: .handle)
        try container.encode("subscription.setScope", forKey: .kind)
        try container.encode(scope, forKey: .scope)
        try container.encode(scopeRevision, forKey: .scopeRevision)
        try container.encode(subscriptionId, forKey: .subscriptionId)
        try container.encode(subscriptionKind, forKey: .subscriptionKind)
    }
}

struct BridgeProductViewResnapshotRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case handle
        case kind
        case scopeRevision
        case subscriptionId
        case subscriptionKind
    }

    let correlation: BridgeProductControlCorrelation
    let handle: String
    let scopeRevision: Int
    let subscriptionId: String
    let subscriptionKind: BridgeProductSubscriptionKind

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductControlCorrelation.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "subscription.resnapshot request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "subscription.resnapshot" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid subscription.resnapshot request kind",
                codingPath: decoder.codingPath
            )
        }
        correlation = try BridgeProductControlCorrelation(from: decoder)
        handle = try container.decode(String.self, forKey: .handle)
        scopeRevision = try container.decode(Int.self, forKey: .scopeRevision)
        subscriptionId = try container.decode(String.self, forKey: .subscriptionId)
        subscriptionKind = try container.decode(BridgeProductSubscriptionKind.self, forKey: .subscriptionKind)
        try BridgeProductContractDecoding.validateIdentifier(handle, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            scopeRevision,
            name: "scopeRevision",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(subscriptionId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try correlation.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(handle, forKey: .handle)
        try container.encode("subscription.resnapshot", forKey: .kind)
        try container.encode(scopeRevision, forKey: .scopeRevision)
        try container.encode(subscriptionId, forKey: .subscriptionId)
        try container.encode(subscriptionKind, forKey: .subscriptionKind)
    }
}

/// Cumulative acknowledgement is keyed by view handle and advances credits as
/// soon as a part is received, independently of atomic batch installation.
struct BridgeProductViewAcknowledgementRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case handle
        case kind
        case paneSessionId
        case receivedThroughDeliverySequence
        case subscriptionId
        case wireVersion
        case workerInstanceId
    }

    let handle: String
    let paneSessionId: String
    let receivedThroughDeliverySequence: Int
    let subscriptionId: String
    let wireVersion: Int
    let workerInstanceId: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "subscription.acknowledge request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "subscription.acknowledge" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid subscription.acknowledge request kind",
                codingPath: decoder.codingPath
            )
        }
        handle = try container.decode(String.self, forKey: .handle)
        paneSessionId = try container.decode(String.self, forKey: .paneSessionId)
        receivedThroughDeliverySequence = try container.decode(Int.self, forKey: .receivedThroughDeliverySequence)
        subscriptionId = try container.decode(String.self, forKey: .subscriptionId)
        wireVersion = try container.decode(Int.self, forKey: .wireVersion)
        workerInstanceId = try container.decode(String.self, forKey: .workerInstanceId)
        try BridgeProductContractDecoding.validateIdentifier(handle, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(paneSessionId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validatePositive(
            receivedThroughDeliverySequence,
            name: "receivedThroughDeliverySequence",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(subscriptionId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateWireVersion(wireVersion, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(workerInstanceId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(handle, forKey: .handle)
        try container.encode("subscription.acknowledge", forKey: .kind)
        try container.encode(paneSessionId, forKey: .paneSessionId)
        try container.encode(receivedThroughDeliverySequence, forKey: .receivedThroughDeliverySequence)
        try container.encode(subscriptionId, forKey: .subscriptionId)
        try container.encode(wireVersion, forKey: .wireVersion)
        try container.encode(workerInstanceId, forKey: .workerInstanceId)
    }
}
