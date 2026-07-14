import Foundation

private enum MetadataAcknowledgementCodingKeys: String, CodingKey, CaseIterable {
    case kind
    case metadataStreamId
    case paneSessionId
    case streamKind
    case streamSequence
    case wireVersion
    case workerInstanceId
}

private enum ContentAcknowledgementCodingKeys: String, CodingKey, CaseIterable {
    case contentRequestId
    case contentSequence
    case kind
    case leaseId
    case paneSessionId
    case streamKind
    case wireVersion
    case workerInstanceId
}

struct BridgeProductMetadataFrameAcknowledgement: Codable, Equatable, Sendable {
    let metadataStreamId: String
    let paneSessionId: String
    let streamSequence: Int
    let wireVersion: Int
    let workerInstanceId: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(
                MetadataAcknowledgementCodingKeys.allCases.map(\.rawValue)
            ),
            contract: "metadata stream.frameObserved request"
        )
        let container = try decoder.container(
            keyedBy: MetadataAcknowledgementCodingKeys.self
        )
        guard try container.decode(String.self, forKey: .kind) == "stream.frameObserved",
            try container.decode(String.self, forKey: .streamKind) == "metadata"
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid metadata stream.frameObserved discriminator",
                codingPath: decoder.codingPath
            )
        }
        self.metadataStreamId = try container.decode(String.self, forKey: .metadataStreamId)
        self.paneSessionId = try container.decode(String.self, forKey: .paneSessionId)
        self.streamSequence = try container.decode(Int.self, forKey: .streamSequence)
        self.wireVersion = try container.decode(Int.self, forKey: .wireVersion)
        self.workerInstanceId = try container.decode(String.self, forKey: .workerInstanceId)
        try BridgeProductContractDecoding.validateIdentifier(
            metadataStreamId,
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(
            paneSessionId,
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateNonnegative(
            streamSequence,
            name: "streamSequence",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateWireVersion(
            wireVersion,
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(
            workerInstanceId,
            codingPath: decoder.codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(
            keyedBy: MetadataAcknowledgementCodingKeys.self
        )
        try container.encode("stream.frameObserved", forKey: .kind)
        try container.encode(metadataStreamId, forKey: .metadataStreamId)
        try container.encode(paneSessionId, forKey: .paneSessionId)
        try container.encode("metadata", forKey: .streamKind)
        try container.encode(streamSequence, forKey: .streamSequence)
        try container.encode(wireVersion, forKey: .wireVersion)
        try container.encode(workerInstanceId, forKey: .workerInstanceId)
    }
}

struct BridgeProductContentFrameAcknowledgement: Codable, Equatable, Sendable {
    let contentRequestId: String
    let contentSequence: Int
    let leaseId: String
    let paneSessionId: String
    let wireVersion: Int
    let workerInstanceId: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(
                ContentAcknowledgementCodingKeys.allCases.map(\.rawValue)
            ),
            contract: "content stream.frameObserved request"
        )
        let container = try decoder.container(
            keyedBy: ContentAcknowledgementCodingKeys.self
        )
        guard try container.decode(String.self, forKey: .kind) == "stream.frameObserved",
            try container.decode(String.self, forKey: .streamKind) == "content"
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid content stream.frameObserved discriminator",
                codingPath: decoder.codingPath
            )
        }
        self.contentRequestId = try container.decode(String.self, forKey: .contentRequestId)
        self.contentSequence = try container.decode(Int.self, forKey: .contentSequence)
        self.leaseId = try container.decode(String.self, forKey: .leaseId)
        self.paneSessionId = try container.decode(String.self, forKey: .paneSessionId)
        self.wireVersion = try container.decode(Int.self, forKey: .wireVersion)
        self.workerInstanceId = try container.decode(String.self, forKey: .workerInstanceId)
        try BridgeProductContractDecoding.validateIdentifier(
            contentRequestId,
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateNonnegative(
            contentSequence,
            name: "contentSequence",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(
            leaseId,
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(
            paneSessionId,
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateWireVersion(
            wireVersion,
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(
            workerInstanceId,
            codingPath: decoder.codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(
            keyedBy: ContentAcknowledgementCodingKeys.self
        )
        try container.encode(contentRequestId, forKey: .contentRequestId)
        try container.encode(contentSequence, forKey: .contentSequence)
        try container.encode("stream.frameObserved", forKey: .kind)
        try container.encode(leaseId, forKey: .leaseId)
        try container.encode(paneSessionId, forKey: .paneSessionId)
        try container.encode("content", forKey: .streamKind)
        try container.encode(wireVersion, forKey: .wireVersion)
        try container.encode(workerInstanceId, forKey: .workerInstanceId)
    }
}

enum BridgeProductCommandPackage: Decodable, Sendable {
    case contentFrameAcknowledgement(BridgeProductContentFrameAcknowledgement)
    case control(BridgeProductControlRequest)
    case metadataFrameAcknowledgement(BridgeProductMetadataFrameAcknowledgement)

    private enum CodingKeys: String, CodingKey {
        case kind
        case streamKind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "stream.frameObserved":
            switch try container.decode(String.self, forKey: .streamKind) {
            case "content":
                self = .contentFrameAcknowledgement(
                    try BridgeProductContentFrameAcknowledgement(from: decoder)
                )
            case "metadata":
                self = .metadataFrameAcknowledgement(
                    try BridgeProductMetadataFrameAcknowledgement(from: decoder)
                )
            default:
                throw BridgeProductContractDecoding.invalidValue(
                    "Invalid stream.frameObserved stream kind",
                    codingPath: decoder.codingPath
                )
            }
        default:
            self = .control(try BridgeProductControlRequest(from: decoder))
        }
    }
}
