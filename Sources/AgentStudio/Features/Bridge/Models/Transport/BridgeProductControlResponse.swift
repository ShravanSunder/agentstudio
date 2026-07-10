import Foundation

enum BridgeProductRequestErrorCode: String, Codable, Equatable, Sendable {
    case invalidRequest = "invalid_request"
    case unauthorized
    case staleWorker = "stale_worker"
    case sequenceConflict = "sequence_conflict"
    case resyncRequired = "resync_required"
    case payloadTooLarge = "payload_too_large"
    case unknownCommand = "unknown_command"
    case `internal`
}

private enum BridgeProductControlResponseIdentityCodingKeys: String, CodingKey, CaseIterable {
    case wireVersion
    case paneSessionId
    case workerInstanceId
    case requestId
    case requestSequence
}

private struct BridgeProductControlResponseIdentity: Codable, Equatable, Sendable {
    static let codingKeyNames = Set(BridgeProductControlResponseIdentityCodingKeys.allCases.map(\.rawValue))

    let wireVersion: Int
    let paneSessionId: String
    let workerInstanceId: String
    let requestId: String
    let requestSequence: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BridgeProductControlResponseIdentityCodingKeys.self)
        self.wireVersion = try container.decode(Int.self, forKey: .wireVersion)
        self.paneSessionId = try container.decode(String.self, forKey: .paneSessionId)
        self.workerInstanceId = try container.decode(String.self, forKey: .workerInstanceId)
        self.requestId = try container.decode(String.self, forKey: .requestId)
        self.requestSequence = try container.decode(Int.self, forKey: .requestSequence)
        try BridgeProductContractDecoding.validateWireVersion(wireVersion, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(paneSessionId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(workerInstanceId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(requestId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validatePositive(
            requestSequence,
            name: "requestSequence",
            codingPath: decoder.codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: BridgeProductControlResponseIdentityCodingKeys.self)
        try container.encode(wireVersion, forKey: .wireVersion)
        try container.encode(paneSessionId, forKey: .paneSessionId)
        try container.encode(workerInstanceId, forKey: .workerInstanceId)
        try container.encode(requestId, forKey: .requestId)
        try container.encode(requestSequence, forKey: .requestSequence)
    }
}

enum BridgeProductControlResponse: Codable, Equatable, Sendable {
    case workerSessionAccepted(BridgeProductWorkerSessionAcceptedResponse)
    case commandAccepted(BridgeProductCommandAcceptedResponse)
    case streamCancelled(BridgeProductStreamCancelledResponse)
    case requestError(BridgeProductRequestErrorResponse)

    private enum KindCodingKeys: String, CodingKey {
        case kind
    }

    var kind: String {
        switch self {
        case .workerSessionAccepted: "workerSession.accepted"
        case .commandAccepted: "command.accepted"
        case .streamCancelled: "stream.cancelled"
        case .requestError: "request.error"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: KindCodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "workerSession.accepted":
            self = .workerSessionAccepted(try BridgeProductWorkerSessionAcceptedResponse(from: decoder))
        case "command.accepted":
            self = .commandAccepted(try BridgeProductCommandAcceptedResponse(from: decoder))
        case "stream.cancelled":
            self = .streamCancelled(try BridgeProductStreamCancelledResponse(from: decoder))
        case "request.error":
            self = .requestError(try BridgeProductRequestErrorResponse(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown Bridge product control response kind"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .workerSessionAccepted(let response): try response.encode(to: encoder)
        case .commandAccepted(let response): try response.encode(to: encoder)
        case .streamCancelled(let response): try response.encode(to: encoder)
        case .requestError(let response): try response.encode(to: encoder)
        }
    }
}

struct BridgeProductWorkerSessionAcceptedResponse: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
    }

    private let identity: BridgeProductControlResponseIdentity

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductControlResponseIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "workerSession.accepted response"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "workerSession.accepted" else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Invalid workerSession.accepted response kind"
            )
        }
        self.identity = try BridgeProductControlResponseIdentity(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("workerSession.accepted", forKey: .kind)
    }
}

struct BridgeProductCommandAcceptedResponse: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
    }

    private let identity: BridgeProductControlResponseIdentity

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductControlResponseIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "command.accepted response"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "command.accepted" else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Invalid command.accepted response kind"
            )
        }
        self.identity = try BridgeProductControlResponseIdentity(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("command.accepted", forKey: .kind)
    }
}

struct BridgeProductStreamCancelledResponse: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case streamId
    }

    private let identity: BridgeProductControlResponseIdentity
    let streamId: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductControlResponseIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "stream.cancelled response"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "stream.cancelled" else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Invalid stream.cancelled response kind"
            )
        }
        self.identity = try BridgeProductControlResponseIdentity(from: decoder)
        self.streamId = try container.decode(String.self, forKey: .streamId)
        try BridgeProductContractDecoding.validateIdentifier(streamId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("stream.cancelled", forKey: .kind)
        try container.encode(streamId, forKey: .streamId)
    }
}

struct BridgeProductRequestErrorResponse: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case code
        case retryable
        case retryAfterMilliseconds
        case nextExpectedRequestSequence
        case safeMessage
    }

    private let identity: BridgeProductControlResponseIdentity
    let code: BridgeProductRequestErrorCode
    let retryable: Bool
    let retryAfterMilliseconds: Int?
    let nextExpectedRequestSequence: Int?
    let safeMessage: String?

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductControlResponseIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "request.error response"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "request.error" else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Invalid request.error response kind"
            )
        }
        self.identity = try BridgeProductControlResponseIdentity(from: decoder)
        self.code = try container.decode(BridgeProductRequestErrorCode.self, forKey: .code)
        self.retryable = try container.decode(Bool.self, forKey: .retryable)
        self.retryAfterMilliseconds = try BridgeProductContractDecoding.decodeOptionalRejectingNull(
            Int.self,
            forKey: .retryAfterMilliseconds,
            from: container,
            codingPath: decoder.codingPath
        )
        self.nextExpectedRequestSequence = try BridgeProductContractDecoding.decodeOptionalRejectingNull(
            Int.self,
            forKey: .nextExpectedRequestSequence,
            from: container,
            codingPath: decoder.codingPath
        )
        self.safeMessage = try BridgeProductContractDecoding.decodeOptionalRejectingNull(
            String.self,
            forKey: .safeMessage,
            from: container,
            codingPath: decoder.codingPath
        )
        if let retryAfterMilliseconds {
            try BridgeProductContractDecoding.validateNonnegative(
                retryAfterMilliseconds,
                name: "retryAfterMilliseconds",
                codingPath: decoder.codingPath
            )
        }
        if let nextExpectedRequestSequence {
            try BridgeProductContractDecoding.validatePositive(
                nextExpectedRequestSequence,
                name: "nextExpectedRequestSequence",
                codingPath: decoder.codingPath
            )
        }
        if let safeMessage {
            try BridgeProductContractDecoding.validateSafeMessage(safeMessage, codingPath: decoder.codingPath)
        }
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("request.error", forKey: .kind)
        try container.encode(code, forKey: .code)
        try container.encode(retryable, forKey: .retryable)
        try container.encodeIfPresent(retryAfterMilliseconds, forKey: .retryAfterMilliseconds)
        try container.encodeIfPresent(nextExpectedRequestSequence, forKey: .nextExpectedRequestSequence)
        try container.encodeIfPresent(safeMessage, forKey: .safeMessage)
    }
}
