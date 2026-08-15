import Foundation

struct BridgeProductReviewComparisonTargetsContentRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contentKind
        case contentRequestId
        case descriptor
        case kind
        case leaseId
        case paneSessionId
        case wireVersion
        case workerDerivationEpoch
        case workerInstanceId
    }

    let contentRequestId: String
    let descriptor: BridgeProductReviewComparisonTargetsContentDescriptor
    let leaseId: String
    let paneSessionId: String
    let wireVersion: Int
    let workerDerivationEpoch: Int
    let workerInstanceId: String

    var admission: BridgeProductContentAdmission {
        .init(
            contentKind: .reviewComparisonTargets,
            contentRequestId: contentRequestId,
            declaredByteLength: nil,
            expectedSha256: nil,
            identity: .reviewComparisonTargets(.init(descriptor: descriptor)),
            leaseId: leaseId,
            maximumBytes: descriptor.maximumBytes,
            paneSessionId: paneSessionId,
            wireVersion: wireVersion,
            workerDerivationEpoch: workerDerivationEpoch,
            workerInstanceId: workerInstanceId
        )
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review comparison targets content request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .contentKind) == "review.comparisonTargets",
            try container.decode(String.self, forKey: .kind) == "content.open"
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Review comparison targets content request kind",
                codingPath: decoder.codingPath
            )
        }
        self.contentRequestId = try container.decode(String.self, forKey: .contentRequestId)
        self.descriptor = try container.decode(
            BridgeProductReviewComparisonTargetsContentDescriptor.self,
            forKey: .descriptor
        )
        self.leaseId = try container.decode(String.self, forKey: .leaseId)
        self.paneSessionId = try container.decode(String.self, forKey: .paneSessionId)
        self.wireVersion = try container.decode(Int.self, forKey: .wireVersion)
        self.workerDerivationEpoch = try container.decode(Int.self, forKey: .workerDerivationEpoch)
        self.workerInstanceId = try container.decode(String.self, forKey: .workerInstanceId)
        try BridgeProductContractDecoding.validateIdentifier(contentRequestId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(leaseId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(paneSessionId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateWireVersion(wireVersion, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            workerDerivationEpoch,
            name: "workerDerivationEpoch",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(workerInstanceId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("review.comparisonTargets", forKey: .contentKind)
        try container.encode(contentRequestId, forKey: .contentRequestId)
        try container.encode(descriptor, forKey: .descriptor)
        try container.encode("content.open", forKey: .kind)
        try container.encode(leaseId, forKey: .leaseId)
        try container.encode(paneSessionId, forKey: .paneSessionId)
        try container.encode(wireVersion, forKey: .wireVersion)
        try container.encode(workerDerivationEpoch, forKey: .workerDerivationEpoch)
        try container.encode(workerInstanceId, forKey: .workerInstanceId)
    }
}
