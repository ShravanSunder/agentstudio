import Foundation

private enum BridgeProductControlRequestIdentityCodingKeys: String, CodingKey, CaseIterable {
    case wireVersion
    case paneSessionId
    case workerInstanceId
    case requestId
    case requestSequence
}

private struct BridgeProductControlRequestIdentity: Codable, Equatable, Sendable {
    static let codingKeyNames = Set(BridgeProductControlRequestIdentityCodingKeys.allCases.map(\.rawValue))

    let wireVersion: Int
    let paneSessionId: String
    let workerInstanceId: String
    let requestId: String
    let requestSequence: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BridgeProductControlRequestIdentityCodingKeys.self)
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
        var container = encoder.container(keyedBy: BridgeProductControlRequestIdentityCodingKeys.self)
        try container.encode(wireVersion, forKey: .wireVersion)
        try container.encode(paneSessionId, forKey: .paneSessionId)
        try container.encode(workerInstanceId, forKey: .workerInstanceId)
        try container.encode(requestId, forKey: .requestId)
        try container.encode(requestSequence, forKey: .requestSequence)
    }
}

enum BridgeProductControlRequest: Codable, Equatable, Sendable {
    case workerSessionOpen(BridgeProductWorkerSessionOpenRequest)
    case productCommand(BridgeProductCommandRequest)
    case streamOpen(BridgeProductStreamOpenRequest)
    case streamCancel(BridgeProductStreamCancelRequest)
    case workerSessionResync(BridgeProductWorkerSessionResyncRequest)

    private enum KindCodingKeys: String, CodingKey {
        case kind
    }

    var kind: String {
        switch self {
        case .workerSessionOpen: "workerSession.open"
        case .productCommand: "product.command"
        case .streamOpen: "stream.open"
        case .streamCancel: "stream.cancel"
        case .workerSessionResync: "workerSession.resync"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: KindCodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "workerSession.open":
            self = .workerSessionOpen(try BridgeProductWorkerSessionOpenRequest(from: decoder))
        case "product.command":
            self = .productCommand(try BridgeProductCommandRequest(from: decoder))
        case "stream.open":
            self = .streamOpen(try BridgeProductStreamOpenRequest(from: decoder))
        case "stream.cancel":
            self = .streamCancel(try BridgeProductStreamCancelRequest(from: decoder))
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
        case .productCommand(let request): try request.encode(to: encoder)
        case .streamOpen(let request): try request.encode(to: encoder)
        case .streamCancel(let request): try request.encode(to: encoder)
        case .workerSessionResync(let request): try request.encode(to: encoder)
        }
    }
}

struct BridgeProductWorkerSessionOpenRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
    }

    private let identity: BridgeProductControlRequestIdentity

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductControlRequestIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "workerSession.open request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "workerSession.open" else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Invalid workerSession.open request kind"
            )
        }
        self.identity = try BridgeProductControlRequestIdentity(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("workerSession.open", forKey: .kind)
    }
}

struct BridgeProductCommandRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case surface
        case sourceGeneration
        case workerEpoch
        case command
    }

    private let identity: BridgeProductControlRequestIdentity
    let surface: BridgeProductSurface
    let sourceGeneration: Int
    let workerEpoch: Int
    let command: BridgeProductCommand

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductControlRequestIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "product.command request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "product.command" else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Invalid product.command request kind"
            )
        }
        self.identity = try BridgeProductControlRequestIdentity(from: decoder)
        self.surface = try container.decode(BridgeProductSurface.self, forKey: .surface)
        self.sourceGeneration = try container.decode(Int.self, forKey: .sourceGeneration)
        self.workerEpoch = try container.decode(Int.self, forKey: .workerEpoch)
        self.command = try container.decode(BridgeProductCommand.self, forKey: .command)
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

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("product.command", forKey: .kind)
        try container.encode(surface, forKey: .surface)
        try container.encode(sourceGeneration, forKey: .sourceGeneration)
        try container.encode(workerEpoch, forKey: .workerEpoch)
        try container.encode(command, forKey: .command)
    }
}

struct BridgeProductStreamOpenRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case surface
        case sourceGeneration
        case workerEpoch
        case streamId
        case sourceRef
        case resumeFromSequence
    }

    private let identity: BridgeProductControlRequestIdentity
    let surface: BridgeProductSurface
    let sourceGeneration: Int
    let workerEpoch: Int
    let streamId: String
    let sourceRef: String
    let resumeFromSequence: Int?

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductControlRequestIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "stream.open request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "stream.open" else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Invalid stream.open request kind"
            )
        }
        self.identity = try BridgeProductControlRequestIdentity(from: decoder)
        self.surface = try container.decode(BridgeProductSurface.self, forKey: .surface)
        self.sourceGeneration = try container.decode(Int.self, forKey: .sourceGeneration)
        self.workerEpoch = try container.decode(Int.self, forKey: .workerEpoch)
        self.streamId = try container.decode(String.self, forKey: .streamId)
        self.sourceRef = try container.decode(String.self, forKey: .sourceRef)
        guard container.contains(.resumeFromSequence) else {
            throw DecodingError.keyNotFound(
                CodingKeys.resumeFromSequence,
                .init(codingPath: decoder.codingPath, debugDescription: "Missing stream resume sequence")
            )
        }
        self.resumeFromSequence = try container.decodeIfPresent(Int.self, forKey: .resumeFromSequence)
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
        try BridgeProductContractDecoding.validateIdentifier(streamId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateOpaqueReference(sourceRef, codingPath: decoder.codingPath)
        if let resumeFromSequence {
            try BridgeProductContractDecoding.validateNonnegative(
                resumeFromSequence,
                name: "resumeFromSequence",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("stream.open", forKey: .kind)
        try container.encode(surface, forKey: .surface)
        try container.encode(sourceGeneration, forKey: .sourceGeneration)
        try container.encode(workerEpoch, forKey: .workerEpoch)
        try container.encode(streamId, forKey: .streamId)
        try container.encode(sourceRef, forKey: .sourceRef)
        try container.encode(resumeFromSequence, forKey: .resumeFromSequence)
    }
}

struct BridgeProductStreamCancelRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case surface
        case streamId
    }

    private let identity: BridgeProductControlRequestIdentity
    let surface: BridgeProductSurface
    let streamId: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductControlRequestIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "stream.cancel request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "stream.cancel" else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Invalid stream.cancel request kind"
            )
        }
        self.identity = try BridgeProductControlRequestIdentity(from: decoder)
        self.surface = try container.decode(BridgeProductSurface.self, forKey: .surface)
        self.streamId = try container.decode(String.self, forKey: .streamId)
        try BridgeProductContractDecoding.validateIdentifier(streamId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("stream.cancel", forKey: .kind)
        try container.encode(surface, forKey: .surface)
        try container.encode(streamId, forKey: .streamId)
    }
}

struct BridgeProductWorkerSessionResyncRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case lastAcceptedRequestSequence
        case activeStreamIds
    }

    private let identity: BridgeProductControlRequestIdentity
    let lastAcceptedRequestSequence: Int
    let activeStreamIds: [String]

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductControlRequestIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "workerSession.resync request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "workerSession.resync" else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Invalid workerSession.resync request kind"
            )
        }
        self.identity = try BridgeProductControlRequestIdentity(from: decoder)
        self.lastAcceptedRequestSequence = try container.decode(Int.self, forKey: .lastAcceptedRequestSequence)
        self.activeStreamIds = try container.decode([String].self, forKey: .activeStreamIds)
        try BridgeProductContractDecoding.validateNonnegative(
            lastAcceptedRequestSequence,
            name: "lastAcceptedRequestSequence",
            codingPath: decoder.codingPath
        )
        guard activeStreamIds.count <= BridgeProductWireContract.maximumActiveStreamCount else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Too many active Bridge product streams")
            )
        }
        for streamId in activeStreamIds {
            try BridgeProductContractDecoding.validateIdentifier(streamId, codingPath: decoder.codingPath)
        }
        guard Set(activeStreamIds).count == activeStreamIds.count else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Duplicate active Bridge product stream id")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("workerSession.resync", forKey: .kind)
        try container.encode(lastAcceptedRequestSequence, forKey: .lastAcceptedRequestSequence)
        try container.encode(activeStreamIds, forKey: .activeStreamIds)
    }
}
