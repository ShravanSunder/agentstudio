import Foundation

enum BridgeProductStreamResumeDisposition: String, Codable, Equatable, Sendable {
    case resumed
    case snapshotRequired = "snapshot_required"
}

enum BridgeProductStreamResetReason: String, Codable, Equatable, Sendable {
    case producerOverflow = "producer_overflow"
    case sequenceGap = "sequence_gap"
    case staleSource = "stale_source"
    case snapshotRequired = "snapshot_required"
}

enum BridgeProductStreamDataFrameKind: String, Codable, Equatable, Sendable {
    case reviewSnapshot = "review.snapshot"
    case reviewDelta = "review.delta"
    case reviewContentDescriptor = "review.contentDescriptor"
    case fileSnapshot = "file.snapshot"
    case fileDelta = "file.delta"
    case fileContentDescriptor = "file.contentDescriptor"
    case surfaceHealth = "surface.health"
}

struct BridgeProductStreamDataPayload: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case frameKind
        case body
    }

    let frameKind: BridgeProductStreamDataFrameKind
    let body: [String: BridgeProductJSONValue]

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge product stream data payload"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.frameKind = try container.decode(BridgeProductStreamDataFrameKind.self, forKey: .frameKind)
        self.body = try container.decode([String: BridgeProductJSONValue].self, forKey: .body)
        try BridgeProductContractDecoding.validateJSONCollectionCount(
            body.count,
            codingPath: decoder.codingPath
        )
        for key in body.keys {
            try BridgeProductContractDecoding.validatePayloadKey(key, codingPath: decoder.codingPath)
        }
    }
}

private enum BridgeProductStreamFrameIdentityCodingKeys: String, CodingKey, CaseIterable {
    case wireVersion
    case paneSessionId
    case workerInstanceId
    case surface
    case streamId
    case sourceGeneration
    case workerEpoch
    case streamSequence
}

private struct BridgeProductStreamFrameIdentity: Codable, Equatable, Sendable {
    static let codingKeyNames = Set(BridgeProductStreamFrameIdentityCodingKeys.allCases.map(\.rawValue))

    let wireVersion: Int
    let paneSessionId: String
    let workerInstanceId: String
    let surface: BridgeProductSurface
    let streamId: String
    let sourceGeneration: Int
    let workerEpoch: Int
    let streamSequence: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BridgeProductStreamFrameIdentityCodingKeys.self)
        self.wireVersion = try container.decode(Int.self, forKey: .wireVersion)
        self.paneSessionId = try container.decode(String.self, forKey: .paneSessionId)
        self.workerInstanceId = try container.decode(String.self, forKey: .workerInstanceId)
        self.surface = try container.decode(BridgeProductSurface.self, forKey: .surface)
        self.streamId = try container.decode(String.self, forKey: .streamId)
        self.sourceGeneration = try container.decode(Int.self, forKey: .sourceGeneration)
        self.workerEpoch = try container.decode(Int.self, forKey: .workerEpoch)
        self.streamSequence = try container.decode(Int.self, forKey: .streamSequence)
        try BridgeProductContractDecoding.validateWireVersion(wireVersion, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(paneSessionId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(workerInstanceId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(streamId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            sourceGeneration,
            name: "sourceGeneration",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateNonnegative(
            workerEpoch,
            name: "workerEpoch",
            codingPath: decoder.codingPath
        )
    }

    func validateAcceptedSequence(codingPath: [any CodingKey]) throws {
        guard streamSequence == 0 else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: codingPath, debugDescription: "Bridge stream.accepted sequence must be zero")
            )
        }
    }

    func validateProgressSequence(codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validatePositive(
            streamSequence,
            name: "streamSequence",
            codingPath: codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: BridgeProductStreamFrameIdentityCodingKeys.self)
        try container.encode(wireVersion, forKey: .wireVersion)
        try container.encode(paneSessionId, forKey: .paneSessionId)
        try container.encode(workerInstanceId, forKey: .workerInstanceId)
        try container.encode(surface, forKey: .surface)
        try container.encode(streamId, forKey: .streamId)
        try container.encode(sourceGeneration, forKey: .sourceGeneration)
        try container.encode(workerEpoch, forKey: .workerEpoch)
        try container.encode(streamSequence, forKey: .streamSequence)
    }
}

enum BridgeProductStreamFrame: Codable, Equatable, Sendable {
    case accepted(BridgeProductStreamAcceptedFrame)
    case data(BridgeProductStreamDataFrame)
    case reset(BridgeProductStreamResetFrame)
    case end(BridgeProductStreamEndFrame)
    case error(BridgeProductStreamErrorFrame)

    private enum KindCodingKeys: String, CodingKey {
        case kind
    }

    var kind: String {
        switch self {
        case .accepted: "stream.accepted"
        case .data: "stream.data"
        case .reset: "stream.reset"
        case .end: "stream.end"
        case .error: "stream.error"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: KindCodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "stream.accepted":
            self = .accepted(try BridgeProductStreamAcceptedFrame(from: decoder))
        case "stream.data":
            self = .data(try BridgeProductStreamDataFrame(from: decoder))
        case "stream.reset":
            self = .reset(try BridgeProductStreamResetFrame(from: decoder))
        case "stream.end":
            self = .end(try BridgeProductStreamEndFrame(from: decoder))
        case "stream.error":
            self = .error(try BridgeProductStreamErrorFrame(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown Bridge product stream frame kind"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .accepted(let frame): try frame.encode(to: encoder)
        case .data(let frame): try frame.encode(to: encoder)
        case .reset(let frame): try frame.encode(to: encoder)
        case .end(let frame): try frame.encode(to: encoder)
        case .error(let frame): try frame.encode(to: encoder)
        }
    }
}

struct BridgeProductStreamAcceptedFrame: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case resumeDisposition
    }

    private let identity: BridgeProductStreamFrameIdentity
    let resumeDisposition: BridgeProductStreamResumeDisposition

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductStreamFrameIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "stream.accepted frame"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "stream.accepted" else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Invalid stream.accepted frame kind"
            )
        }
        self.identity = try BridgeProductStreamFrameIdentity(from: decoder)
        self.resumeDisposition = try container.decode(
            BridgeProductStreamResumeDisposition.self,
            forKey: .resumeDisposition
        )
        try identity.validateAcceptedSequence(codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("stream.accepted", forKey: .kind)
        try container.encode(resumeDisposition, forKey: .resumeDisposition)
    }
}

struct BridgeProductStreamDataFrame: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case payload
    }

    private let identity: BridgeProductStreamFrameIdentity
    let payload: BridgeProductStreamDataPayload

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductStreamFrameIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "stream.data frame"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "stream.data" else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Invalid stream.data frame kind"
            )
        }
        self.identity = try BridgeProductStreamFrameIdentity(from: decoder)
        self.payload = try container.decode(BridgeProductStreamDataPayload.self, forKey: .payload)
        try identity.validateProgressSequence(codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("stream.data", forKey: .kind)
        try container.encode(payload, forKey: .payload)
    }
}

struct BridgeProductStreamResetFrame: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case reason
    }

    private let identity: BridgeProductStreamFrameIdentity
    let reason: BridgeProductStreamResetReason

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductStreamFrameIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "stream.reset frame"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "stream.reset" else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Invalid stream.reset frame kind"
            )
        }
        self.identity = try BridgeProductStreamFrameIdentity(from: decoder)
        self.reason = try container.decode(BridgeProductStreamResetReason.self, forKey: .reason)
        try identity.validateProgressSequence(codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("stream.reset", forKey: .kind)
        try container.encode(reason, forKey: .reason)
    }
}

struct BridgeProductStreamEndFrame: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
    }

    private let identity: BridgeProductStreamFrameIdentity

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductStreamFrameIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "stream.end frame"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "stream.end" else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Invalid stream.end frame kind"
            )
        }
        self.identity = try BridgeProductStreamFrameIdentity(from: decoder)
        try identity.validateProgressSequence(codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("stream.end", forKey: .kind)
    }
}

struct BridgeProductStreamErrorFrame: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case code
        case retryable
        case safeMessage
    }

    private let identity: BridgeProductStreamFrameIdentity
    let code: BridgeProductRequestErrorCode
    let retryable: Bool
    let safeMessage: String?

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductStreamFrameIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "stream.error frame"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "stream.error" else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Invalid stream.error frame kind"
            )
        }
        self.identity = try BridgeProductStreamFrameIdentity(from: decoder)
        self.code = try container.decode(BridgeProductRequestErrorCode.self, forKey: .code)
        self.retryable = try container.decode(Bool.self, forKey: .retryable)
        self.safeMessage = try BridgeProductContractDecoding.decodeOptionalRejectingNull(
            String.self,
            forKey: .safeMessage,
            from: container,
            codingPath: decoder.codingPath
        )
        try identity.validateProgressSequence(codingPath: decoder.codingPath)
        if let safeMessage {
            try BridgeProductContractDecoding.validateSafeMessage(safeMessage, codingPath: decoder.codingPath)
        }
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("stream.error", forKey: .kind)
        try container.encode(code, forKey: .code)
        try container.encode(retryable, forKey: .retryable)
        try container.encodeIfPresent(safeMessage, forKey: .safeMessage)
    }
}
