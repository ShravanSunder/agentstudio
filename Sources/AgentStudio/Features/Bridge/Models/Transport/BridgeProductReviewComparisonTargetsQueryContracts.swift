import Foundation

struct BridgeProductReviewComparisonTargetsQueryResult: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case descriptor
    }

    let descriptor: BridgeProductReviewComparisonTargetsContentDescriptor

    init(descriptor: BridgeProductReviewComparisonTargetsContentDescriptor) {
        self.descriptor = descriptor
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "review.comparisonTargets.query result"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        descriptor = try container.decode(
            BridgeProductReviewComparisonTargetsContentDescriptor.self,
            forKey: .descriptor
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(descriptor, forKey: .descriptor)
    }
}
