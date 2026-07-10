import Foundation

enum BridgeProductWireContract {
    static let version = 1
    static let capabilityByteLength = 32
    static let maximumIdentifierByteLength = 128
    static let maximumOpaqueReferenceByteLength = 256
    static let maximumSafeMessageByteLength = 256
    static let maximumActiveStreamCount = 64
    static let maximumSafeInteger = 9_007_199_254_740_991
    static let maximumJSONCollectionCount = 64
    static let maximumJSONDepth = 8
    static let maximumJSONValueStringByteLength = 256
    static let maximumControlRequestBytes = 64 * 1024
    static let maximumStreamFrameBytes = 256 * 1024
    static let maximumQueuedStreamFrames = 64
    static let maximumQueuedStreamBytes = 4 * 1024 * 1024
    static let maximumResourceBytes = 2 * 1024 * 1024
    static let terminalFrameReserve = 1
}

enum BridgeProductSurface: String, Codable, Equatable, Sendable {
    case review
    case file
}

enum BridgeProductCommandName: String, Codable, Equatable, Sendable {
    case reviewLoad = "review.load"
    case reviewRefresh = "review.refresh"
    case reviewMarkFileViewed = "review.markFileViewed"
    case reviewMetadataInterestUpdate = "review.metadataInterest.update"
    case fileOpen = "file.open"
    case fileRefresh = "file.refresh"
    case fileRequestDescriptor = "file.requestDescriptor"
    case viewerModeUpdate = "viewerMode.update"
}

struct BridgeProductCommand: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case name
        case payload
    }

    let name: BridgeProductCommandName
    let payload: [String: BridgeProductJSONValue]

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge product command"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(BridgeProductCommandName.self, forKey: .name)
        self.payload = try container.decode([String: BridgeProductJSONValue].self, forKey: .payload)
        try BridgeProductContractDecoding.validateJSONCollectionCount(
            payload.count,
            codingPath: decoder.codingPath
        )
        for key in payload.keys {
            try BridgeProductContractDecoding.validatePayloadKey(key, codingPath: decoder.codingPath)
        }
    }
}

enum BridgeProductJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([Self])
    case object([String: Self])

    init(from decoder: Decoder) throws {
        let payloadDepth = max(0, decoder.codingPath.count - 2)
        guard payloadDepth <= BridgeProductWireContract.maximumJSONDepth else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product JSON nesting exceeds the depth cap",
                codingPath: decoder.codingPath
            )
        }
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            try BridgeProductContractDecoding.validateJSONNumber(value, codingPath: decoder.codingPath)
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            try BridgeProductContractDecoding.validateJSONValueString(value, codingPath: decoder.codingPath)
            self = .string(value)
        } else if let value = try? container.decode([Self].self) {
            try BridgeProductContractDecoding.validateJSONCollectionCount(
                value.count,
                codingPath: decoder.codingPath
            )
            self = .array(value)
        } else if let value = try? container.decode([String: Self].self) {
            try BridgeProductContractDecoding.validateJSONCollectionCount(
                value.count,
                codingPath: decoder.codingPath
            )
            for key in value.keys {
                try BridgeProductContractDecoding.validatePayloadKey(key, codingPath: decoder.codingPath)
            }
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported Bridge product JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

struct BridgeProductResourceRequestIdentity: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case wireVersion
        case paneSessionId
        case workerInstanceId
        case surface
        case sourceGeneration
        case workerEpoch
        case resourceRequestId
        case leaseId
        case resourceKind
        case resourceRef
        case maximumBytes
    }

    let wireVersion: Int
    let paneSessionId: String
    let workerInstanceId: String
    let surface: BridgeProductSurface
    let sourceGeneration: Int
    let workerEpoch: Int
    let resourceRequestId: String
    let leaseId: String
    let resourceKind: BridgeProductResourceKind
    let resourceRef: String
    let maximumBytes: Int

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge product resource request identity"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.wireVersion = try container.decode(Int.self, forKey: .wireVersion)
        self.paneSessionId = try container.decode(String.self, forKey: .paneSessionId)
        self.workerInstanceId = try container.decode(String.self, forKey: .workerInstanceId)
        self.surface = try container.decode(BridgeProductSurface.self, forKey: .surface)
        self.sourceGeneration = try container.decode(Int.self, forKey: .sourceGeneration)
        self.workerEpoch = try container.decode(Int.self, forKey: .workerEpoch)
        self.resourceRequestId = try container.decode(String.self, forKey: .resourceRequestId)
        self.leaseId = try container.decode(String.self, forKey: .leaseId)
        self.resourceKind = try container.decode(BridgeProductResourceKind.self, forKey: .resourceKind)
        self.resourceRef = try container.decode(String.self, forKey: .resourceRef)
        self.maximumBytes = try container.decode(Int.self, forKey: .maximumBytes)
        try BridgeProductContractDecoding.validateWireVersion(wireVersion, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(paneSessionId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(workerInstanceId, codingPath: decoder.codingPath)
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
        try BridgeProductContractDecoding.validateIdentifier(
            resourceRequestId,
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(leaseId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateOpaqueReference(resourceRef, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validatePositive(
            maximumBytes,
            name: "maximumBytes",
            codingPath: decoder.codingPath
        )
        guard maximumBytes <= BridgeProductWireContract.maximumResourceBytes else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product resource request exceeds the bootstrap byte ceiling",
                codingPath: decoder.codingPath
            )
        }
    }
}

struct BridgeProductAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

enum BridgeProductContractDecoding {
    static func rejectUnknownKeys(
        from decoder: Decoder,
        allowedKeys: Set<String>,
        contract: String
    ) throws {
        let container = try decoder.container(keyedBy: BridgeProductAnyCodingKey.self)
        for key in container.allKeys where !allowedKeys.contains(key.stringValue) {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Unexpected \(contract) key"
            )
        }
    }

    static func validateWireVersion(_ value: Int, codingPath: [any CodingKey]) throws {
        guard value == BridgeProductWireContract.version else {
            throw invalidValue("Bridge product wireVersion must be 1", codingPath: codingPath)
        }
    }

    static func validateIdentifier(_ value: String, codingPath: [any CodingKey]) throws {
        let identifierCharacters = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-")
        guard
            !value.isEmpty,
            value.utf8.count <= BridgeProductWireContract.maximumIdentifierByteLength,
            value.unicodeScalars.allSatisfy(identifierCharacters.contains)
        else {
            throw invalidValue("Invalid Bridge product identifier", codingPath: codingPath)
        }
    }

    static func validateOpaqueReference(_ value: String, codingPath: [any CodingKey]) throws {
        guard
            !value.isEmpty,
            value.utf8.count <= BridgeProductWireContract.maximumOpaqueReferenceByteLength,
            value.unicodeScalars.allSatisfy({ $0.value >= 0x21 && $0.value <= 0x7e })
        else {
            throw invalidValue("Invalid Bridge product opaque reference", codingPath: codingPath)
        }
    }

    static func validatePayloadKey(_ value: String, codingPath: [any CodingKey]) throws {
        guard !value.isEmpty, value.utf8.count <= BridgeProductWireContract.maximumIdentifierByteLength else {
            throw invalidValue("Invalid Bridge product payload key", codingPath: codingPath)
        }
    }

    static func validateSafeMessage(_ value: String, codingPath: [any CodingKey]) throws {
        guard !value.isEmpty, value.utf8.count <= BridgeProductWireContract.maximumSafeMessageByteLength else {
            throw invalidValue("Invalid Bridge product safe message", codingPath: codingPath)
        }
    }

    static func validatePositive(_ value: Int, name: String, codingPath: [any CodingKey]) throws {
        guard value > 0, value <= BridgeProductWireContract.maximumSafeInteger else {
            throw invalidValue(
                "Bridge product \(name) must be a positive safe integer",
                codingPath: codingPath
            )
        }
    }

    static func validateNonnegative(_ value: Int, name: String, codingPath: [any CodingKey]) throws {
        guard value >= 0, value <= BridgeProductWireContract.maximumSafeInteger else {
            throw invalidValue(
                "Bridge product \(name) must be a nonnegative safe integer",
                codingPath: codingPath
            )
        }
    }

    static func validateJSONNumber(_ value: Double, codingPath: [any CodingKey]) throws {
        guard value.isFinite, abs(value) <= Double(BridgeProductWireContract.maximumSafeInteger) else {
            throw invalidValue("Bridge product JSON number exceeds the shared range", codingPath: codingPath)
        }
    }

    static func validateJSONValueString(_ value: String, codingPath: [any CodingKey]) throws {
        guard value.utf8.count <= BridgeProductWireContract.maximumJSONValueStringByteLength else {
            throw invalidValue("Bridge product JSON string exceeds the byte cap", codingPath: codingPath)
        }
    }

    static func validateJSONCollectionCount(_ count: Int, codingPath: [any CodingKey]) throws {
        guard count <= BridgeProductWireContract.maximumJSONCollectionCount else {
            throw invalidValue("Bridge product JSON collection exceeds the item cap", codingPath: codingPath)
        }
    }

    static func decodeOptionalRejectingNull<DecodedValue: Decodable, Key: CodingKey>(
        _ type: DecodedValue.Type,
        forKey key: Key,
        from container: KeyedDecodingContainer<Key>,
        codingPath: [any CodingKey]
    ) throws -> DecodedValue? {
        guard container.contains(key) else { return nil }
        guard try !container.decodeNil(forKey: key) else {
            throw invalidValue("Bridge product optional field cannot be null", codingPath: codingPath)
        }
        return try container.decode(type, forKey: key)
    }

    static func invalidValue(_ description: String, codingPath: [any CodingKey]) -> DecodingError {
        .dataCorrupted(.init(codingPath: codingPath, debugDescription: description))
    }
}
