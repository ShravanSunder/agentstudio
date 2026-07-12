import Foundation

private enum BridgeProductContentAcceptedIdentityCodingKeys: String, CodingKey, CaseIterable {
    case contentRequestId
    case contentSequence
    case identity
    case leaseId
    case paneSessionId
    case wireVersion
    case workerDerivationEpoch
    case workerInstanceId
}

struct BridgeProductContentFrameIdentity: Codable, Equatable, Sendable {
    static let codingKeyNames = Set(
        BridgeProductContentAcceptedIdentityCodingKeys.allCases.map(\.rawValue)
    )

    let contentRequestId: String
    let contentSequence: Int
    let identity: BridgeProductContentIdentity
    let leaseId: String
    let paneSessionId: String
    let wireVersion: Int
    let workerDerivationEpoch: Int
    let workerInstanceId: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: BridgeProductContentAcceptedIdentityCodingKeys.self
        )
        self.contentRequestId = try container.decode(String.self, forKey: .contentRequestId)
        self.contentSequence = try container.decode(Int.self, forKey: .contentSequence)
        self.identity = try container.decode(BridgeProductContentIdentity.self, forKey: .identity)
        self.leaseId = try container.decode(String.self, forKey: .leaseId)
        self.paneSessionId = try container.decode(String.self, forKey: .paneSessionId)
        self.wireVersion = try container.decode(Int.self, forKey: .wireVersion)
        self.workerDerivationEpoch = try container.decode(
            Int.self,
            forKey: .workerDerivationEpoch
        )
        self.workerInstanceId = try container.decode(String.self, forKey: .workerInstanceId)
        try BridgeProductContractDecoding.validateIdentifier(
            contentRequestId,
            codingPath: decoder.codingPath
        )
        guard contentSequence == 0 else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product content.accepted sequence must be zero",
                codingPath: decoder.codingPath
            )
        }
        try BridgeProductContractDecoding.validateIdentifier(leaseId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(
            paneSessionId,
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateWireVersion(
            wireVersion,
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateNonnegative(
            workerDerivationEpoch,
            name: "workerDerivationEpoch",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(
            workerInstanceId,
            codingPath: decoder.codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(
            keyedBy: BridgeProductContentAcceptedIdentityCodingKeys.self
        )
        try container.encode(contentRequestId, forKey: .contentRequestId)
        try container.encode(contentSequence, forKey: .contentSequence)
        try container.encode(identity, forKey: .identity)
        try container.encode(leaseId, forKey: .leaseId)
        try container.encode(paneSessionId, forKey: .paneSessionId)
        try container.encode(wireVersion, forKey: .wireVersion)
        try container.encode(workerDerivationEpoch, forKey: .workerDerivationEpoch)
        try container.encode(workerInstanceId, forKey: .workerInstanceId)
    }
}

struct BridgeProductContentAcceptedHeader: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case declaredByteLength
        case expectedSha256
        case kind
        case maximumBytes
    }

    let frameIdentity: BridgeProductContentFrameIdentity
    let declaredByteLength: Int?
    let expectedSha256: String?
    let maximumBytes: Int

    var contentRequestId: String { frameIdentity.contentRequestId }
    var contentSequence: Int { frameIdentity.contentSequence }
    var identity: BridgeProductContentIdentity { frameIdentity.identity }
    var leaseId: String { frameIdentity.leaseId }
    var paneSessionId: String { frameIdentity.paneSessionId }
    var wireVersion: Int { frameIdentity.wireVersion }
    var workerDerivationEpoch: Int { frameIdentity.workerDerivationEpoch }
    var workerInstanceId: String { frameIdentity.workerInstanceId }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductContentFrameIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "content.accepted header"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "content.accepted" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Bridge product content.accepted kind",
                codingPath: decoder.codingPath
            )
        }
        self.frameIdentity = try BridgeProductContentFrameIdentity(from: decoder)
        self.declaredByteLength = try BridgeProductContractDecoding.decodeRequiredNullable(
            Int.self,
            forKey: .declaredByteLength,
            from: container,
            codingPath: decoder.codingPath
        )
        self.expectedSha256 = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .expectedSha256,
            from: container,
            codingPath: decoder.codingPath
        )
        self.maximumBytes = try container.decode(Int.self, forKey: .maximumBytes)
        try validateBounds(codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try frameIdentity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("content.accepted", forKey: .kind)
        try container.encode(declaredByteLength, forKey: .declaredByteLength)
        try container.encode(expectedSha256, forKey: .expectedSha256)
        try container.encode(maximumBytes, forKey: .maximumBytes)
    }

    private func validateBounds(codingPath: [any CodingKey]) throws {
        if let declaredByteLength {
            try BridgeProductContractDecoding.validateNonnegative(
                declaredByteLength,
                name: "declaredByteLength",
                codingPath: codingPath
            )
            try BridgeProductContractDecoding.validateMaximum(
                declaredByteLength,
                maximum: BridgeProductWireContract.maximumContentBytes,
                name: "declaredByteLength",
                codingPath: codingPath
            )
        }
        if let expectedSha256 {
            try BridgeProductContractDecoding.validateSHA256(expectedSha256, codingPath: codingPath)
        }
        try BridgeProductContractDecoding.validatePositive(
            maximumBytes,
            name: "maximumBytes",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            maximumBytes,
            maximum: BridgeProductWireContract.maximumContentBytes,
            name: "maximumBytes",
            codingPath: codingPath
        )
        guard declaredByteLength.map({ $0 <= maximumBytes }) ?? true,
            case .fileContent(let fileIdentity) = identity,
            fileIdentity.window.maximumBytes == maximumBytes
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product accepted content bounds are inconsistent",
                codingPath: codingPath
            )
        }
    }
}

struct BridgeProductContentDataHeader: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contentSequence
        case kind
        case offsetBytes
    }

    let contentSequence: Int
    let offsetBytes: Int

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "content.data header"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.contentSequence = try container.decode(Int.self, forKey: .contentSequence)
        guard try container.decode(String.self, forKey: .kind) == "content.data" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Bridge product content.data kind",
                codingPath: decoder.codingPath
            )
        }
        self.offsetBytes = try container.decode(Int.self, forKey: .offsetBytes)
        try validateContentProgressSequence(contentSequence, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            offsetBytes,
            name: "offsetBytes",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            offsetBytes,
            maximum: BridgeProductWireContract.maximumContentBytes,
            name: "offsetBytes",
            codingPath: decoder.codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contentSequence, forKey: .contentSequence)
        try container.encode("content.data", forKey: .kind)
        try container.encode(offsetBytes, forKey: .offsetBytes)
    }
}

struct BridgeProductContentEndHeader: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contentSequence
        case endOfSource
        case kind
        case observedByteLength
        case observedSha256
    }

    let contentSequence: Int
    let endOfSource: Bool
    let observedByteLength: Int
    let observedSha256: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "content.end header"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.contentSequence = try container.decode(Int.self, forKey: .contentSequence)
        guard try container.decode(String.self, forKey: .kind) == "content.end" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Bridge product content.end kind",
                codingPath: decoder.codingPath
            )
        }
        self.endOfSource = try container.decode(Bool.self, forKey: .endOfSource)
        self.observedByteLength = try container.decode(Int.self, forKey: .observedByteLength)
        self.observedSha256 = try container.decode(String.self, forKey: .observedSha256)
        try validateContentProgressSequence(contentSequence, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            observedByteLength,
            name: "observedByteLength",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            observedByteLength,
            maximum: BridgeProductWireContract.maximumContentBytes,
            name: "observedByteLength",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateSHA256(
            observedSha256,
            codingPath: decoder.codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contentSequence, forKey: .contentSequence)
        try container.encode(endOfSource, forKey: .endOfSource)
        try container.encode("content.end", forKey: .kind)
        try container.encode(observedByteLength, forKey: .observedByteLength)
        try container.encode(observedSha256, forKey: .observedSha256)
    }
}

struct BridgeProductContentErrorHeader: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case code
        case contentSequence
        case kind
        case retryable
        case safeMessage
    }

    let contentSequence: Int
    let code: BridgeProductRequestErrorCode
    let retryable: Bool
    let safeMessage: String?

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "content.error header"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.code = try container.decode(BridgeProductRequestErrorCode.self, forKey: .code)
        self.contentSequence = try container.decode(Int.self, forKey: .contentSequence)
        guard try container.decode(String.self, forKey: .kind) == "content.error" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Bridge product content.error kind",
                codingPath: decoder.codingPath
            )
        }
        self.retryable = try container.decode(Bool.self, forKey: .retryable)
        self.safeMessage = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .safeMessage,
            from: container,
            codingPath: decoder.codingPath
        )
        try validateContentProgressSequence(contentSequence, codingPath: decoder.codingPath)
        if let safeMessage {
            try BridgeProductContractDecoding.validateSafeMessage(
                safeMessage,
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(contentSequence, forKey: .contentSequence)
        try container.encode("content.error", forKey: .kind)
        try container.encode(retryable, forKey: .retryable)
        try container.encode(safeMessage, forKey: .safeMessage)
    }
}

struct BridgeProductContentResetHeader: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contentSequence
        case kind
        case reason
    }

    let contentSequence: Int
    let reason: BridgeProductResetReason

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "content.reset header"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.contentSequence = try container.decode(Int.self, forKey: .contentSequence)
        guard try container.decode(String.self, forKey: .kind) == "content.reset" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Bridge product content.reset kind",
                codingPath: decoder.codingPath
            )
        }
        self.reason = try container.decode(BridgeProductResetReason.self, forKey: .reason)
        try validateContentProgressSequence(contentSequence, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contentSequence, forKey: .contentSequence)
        try container.encode("content.reset", forKey: .kind)
        try container.encode(reason, forKey: .reason)
    }
}

enum BridgeProductContentHeader: Codable, Equatable, Sendable {
    case accepted(BridgeProductContentAcceptedHeader)
    case data(BridgeProductContentDataHeader)
    case end(BridgeProductContentEndHeader)
    case error(BridgeProductContentErrorHeader)
    case reset(BridgeProductContentResetHeader)

    private enum CodingKeys: String, CodingKey {
        case kind
    }

    var kind: String {
        switch self {
        case .accepted: "content.accepted"
        case .data: "content.data"
        case .end: "content.end"
        case .error: "content.error"
        case .reset: "content.reset"
        }
    }

    var contentSequence: Int {
        switch self {
        case .accepted(let header): header.contentSequence
        case .data(let header): header.contentSequence
        case .end(let header): header.contentSequence
        case .error(let header): header.contentSequence
        case .reset(let header): header.contentSequence
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "content.accepted":
            self = .accepted(try BridgeProductContentAcceptedHeader(from: decoder))
        case "content.data":
            self = .data(try BridgeProductContentDataHeader(from: decoder))
        case "content.end":
            self = .end(try BridgeProductContentEndHeader(from: decoder))
        case "content.error":
            self = .error(try BridgeProductContentErrorHeader(from: decoder))
        case "content.reset":
            self = .reset(try BridgeProductContentResetHeader(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown Bridge product content header kind"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .accepted(let header): try header.encode(to: encoder)
        case .data(let header): try header.encode(to: encoder)
        case .end(let header): try header.encode(to: encoder)
        case .error(let header): try header.encode(to: encoder)
        case .reset(let header): try header.encode(to: encoder)
        }
    }
}

struct BridgeProductContentFrame: Equatable, Sendable {
    let header: BridgeProductContentHeader
    let payload: Data
}

struct BridgeProductContentCompleteTerminal: Equatable, Sendable {
    let bytes: Data
    let contentKind: BridgeProductContentKind
    let descriptorId: String
    let endOfSource: Bool
    let observedSha256: String
}

struct BridgeProductContentErrorTerminal: Equatable, Sendable {
    let code: BridgeProductRequestErrorCode
    let contentKind: BridgeProductContentKind
    let descriptorId: String
    let retryable: Bool
    let safeMessage: String?
}

struct BridgeProductContentResetTerminal: Equatable, Sendable {
    let contentKind: BridgeProductContentKind
    let descriptorId: String
    let reason: BridgeProductResetReason
    let retryable: Bool
}

enum BridgeProductContentTerminalResult: Equatable, Sendable {
    case complete(BridgeProductContentCompleteTerminal)
    case error(BridgeProductContentErrorTerminal)
    case reset(BridgeProductContentResetTerminal)
}

private func validateContentProgressSequence(
    _ contentSequence: Int,
    codingPath: [any CodingKey]
) throws {
    try BridgeProductContractDecoding.validatePositive(
        contentSequence,
        name: "contentSequence",
        codingPath: codingPath
    )
    try BridgeProductContractDecoding.validateMaximum(
        contentSequence,
        maximum: Int(UInt32.max),
        name: "contentSequence",
        codingPath: codingPath
    )
}
