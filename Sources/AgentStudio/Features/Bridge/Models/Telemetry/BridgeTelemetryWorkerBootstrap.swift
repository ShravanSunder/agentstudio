import Foundation

enum BridgeTelemetryWorkerWireContract {
    static let schemaVersion = 2
    static let capabilityByteLength = 32
    static let capabilityHeaderName = "X-AgentStudio-Bridge-Telemetry-Capability"
}

enum BridgeTelemetryProducerId: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case main
    case comm
}

enum BridgeTelemetryLossReason: String, Codable, Equatable, Sendable {
    case creditExhausted = "credit_exhausted"
    case encodedByteCap = "encoded_byte_cap"
    case queueSaturated = "queue_saturated"
    case outboxSaturated = "outbox_saturated"
    case producerFailure = "producer_failure"
}

struct BridgeTelemetryWorkerPolicy: Codable, Equatable, Sendable {
    let initialControlCredits: Int
    let initialSampleCredits: Int
    let compactSampleMaxEncodedBytes: Int
    let producerLossKeyCap: Int
    let producerPreReadyBufferMaxBytes: Int
    let producerPreReadyBufferMaxSamples: Int
    let workerBufferMaxBytes: Int
    let workerBufferMaxSamples: Int
    let batchMaxBytes: Int
    let batchMaxSamples: Int
    let outboxMaxBytes: Int
    let outboxMaxCount: Int
    let maxRetryAttempts: Int
    let minimumFlushIntervalMilliseconds: Int
    let drainTimeoutMilliseconds: Int

    static let live = Self(
        initialControlCredits: 4,
        initialSampleCredits: 128,
        compactSampleMaxEncodedBytes: 16 * 1024,
        producerLossKeyCap: 64,
        producerPreReadyBufferMaxBytes: 64 * 1024,
        producerPreReadyBufferMaxSamples: 128,
        workerBufferMaxBytes: 256 * 1024,
        workerBufferMaxSamples: 256,
        batchMaxBytes: 64 * 1024,
        batchMaxSamples: 128,
        outboxMaxBytes: 256 * 1024,
        outboxMaxCount: 4,
        maxRetryAttempts: 3,
        minimumFlushIntervalMilliseconds: 250,
        drainTimeoutMilliseconds: 2000
    )

    init(
        initialControlCredits: Int,
        initialSampleCredits: Int,
        compactSampleMaxEncodedBytes: Int,
        producerLossKeyCap: Int,
        producerPreReadyBufferMaxBytes: Int,
        producerPreReadyBufferMaxSamples: Int,
        workerBufferMaxBytes: Int,
        workerBufferMaxSamples: Int,
        batchMaxBytes: Int,
        batchMaxSamples: Int,
        outboxMaxBytes: Int,
        outboxMaxCount: Int,
        maxRetryAttempts: Int,
        minimumFlushIntervalMilliseconds: Int,
        drainTimeoutMilliseconds: Int
    ) {
        self.initialControlCredits = initialControlCredits
        self.initialSampleCredits = initialSampleCredits
        self.compactSampleMaxEncodedBytes = compactSampleMaxEncodedBytes
        self.producerLossKeyCap = producerLossKeyCap
        self.producerPreReadyBufferMaxBytes = producerPreReadyBufferMaxBytes
        self.producerPreReadyBufferMaxSamples = producerPreReadyBufferMaxSamples
        self.workerBufferMaxBytes = workerBufferMaxBytes
        self.workerBufferMaxSamples = workerBufferMaxSamples
        self.batchMaxBytes = batchMaxBytes
        self.batchMaxSamples = batchMaxSamples
        self.outboxMaxBytes = outboxMaxBytes
        self.outboxMaxCount = outboxMaxCount
        self.maxRetryAttempts = maxRetryAttempts
        self.minimumFlushIntervalMilliseconds = minimumFlushIntervalMilliseconds
        self.drainTimeoutMilliseconds = drainTimeoutMilliseconds
    }

    init(from decoder: Decoder) throws {
        try BridgeTelemetryContractValidation.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge telemetry worker policy"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            initialControlCredits: try container.decode(Int.self, forKey: .initialControlCredits),
            initialSampleCredits: try container.decode(Int.self, forKey: .initialSampleCredits),
            compactSampleMaxEncodedBytes: try container.decode(Int.self, forKey: .compactSampleMaxEncodedBytes),
            producerLossKeyCap: try container.decode(Int.self, forKey: .producerLossKeyCap),
            producerPreReadyBufferMaxBytes: try container.decode(
                Int.self,
                forKey: .producerPreReadyBufferMaxBytes
            ),
            producerPreReadyBufferMaxSamples: try container.decode(
                Int.self,
                forKey: .producerPreReadyBufferMaxSamples
            ),
            workerBufferMaxBytes: try container.decode(Int.self, forKey: .workerBufferMaxBytes),
            workerBufferMaxSamples: try container.decode(Int.self, forKey: .workerBufferMaxSamples),
            batchMaxBytes: try container.decode(Int.self, forKey: .batchMaxBytes),
            batchMaxSamples: try container.decode(Int.self, forKey: .batchMaxSamples),
            outboxMaxBytes: try container.decode(Int.self, forKey: .outboxMaxBytes),
            outboxMaxCount: try container.decode(Int.self, forKey: .outboxMaxCount),
            maxRetryAttempts: try container.decode(Int.self, forKey: .maxRetryAttempts),
            minimumFlushIntervalMilliseconds: try container.decode(
                Int.self,
                forKey: .minimumFlushIntervalMilliseconds
            ),
            drainTimeoutMilliseconds: try container.decode(Int.self, forKey: .drainTimeoutMilliseconds)
        )
        try validate(codingPath: decoder.codingPath)
    }

    func validate(codingPath: [any CodingKey]) throws {
        let positiveValues = [
            initialControlCredits,
            initialSampleCredits,
            compactSampleMaxEncodedBytes,
            producerLossKeyCap,
            producerPreReadyBufferMaxBytes,
            producerPreReadyBufferMaxSamples,
            workerBufferMaxBytes,
            workerBufferMaxSamples,
            batchMaxBytes,
            batchMaxSamples,
            outboxMaxBytes,
            outboxMaxCount,
            maxRetryAttempts,
            drainTimeoutMilliseconds,
        ]
        guard positiveValues.allSatisfy({ $0 > 0 }), minimumFlushIntervalMilliseconds >= 0 else {
            throw BridgeTelemetryContractValidation.invalidValue(
                "Invalid Bridge telemetry worker policy",
                codingPath: codingPath
            )
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case initialControlCredits
        case initialSampleCredits
        case compactSampleMaxEncodedBytes
        case producerLossKeyCap
        case producerPreReadyBufferMaxBytes
        case producerPreReadyBufferMaxSamples
        case workerBufferMaxBytes
        case workerBufferMaxSamples
        case batchMaxBytes
        case batchMaxSamples
        case outboxMaxBytes
        case outboxMaxCount
        case maxRetryAttempts
        case minimumFlushIntervalMilliseconds
        case drainTimeoutMilliseconds
    }
}

struct BridgeTelemetryWorkerBootstrap: Codable, Equatable, Sendable {
    let enabledScopes: [BridgeTelemetryScope]
    let endpointUrl: String
    let telemetryCapability: String
    let telemetryCapabilityDigest: String
    let telemetrySessionId: String
    let policy: BridgeTelemetryWorkerPolicy

    init(
        enabledScopes: [BridgeTelemetryScope],
        endpointUrl: String,
        telemetryCapability: String,
        telemetryCapabilityDigest: String,
        telemetrySessionId: String,
        policy: BridgeTelemetryWorkerPolicy
    ) throws {
        self.enabledScopes = enabledScopes
        self.endpointUrl = endpointUrl
        self.telemetryCapability = telemetryCapability
        self.telemetryCapabilityDigest = telemetryCapabilityDigest
        self.telemetrySessionId = telemetrySessionId
        self.policy = policy
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeTelemetryContractValidation.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge telemetry worker bootstrap"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabledScopes = try container.decode([BridgeTelemetryScope].self, forKey: .enabledScopes)
        self.endpointUrl = try container.decode(String.self, forKey: .endpointUrl)
        self.telemetryCapability = try container.decode(String.self, forKey: .telemetryCapability)
        self.telemetryCapabilityDigest = try container.decode(String.self, forKey: .telemetryCapabilityDigest)
        self.telemetrySessionId = try container.decode(String.self, forKey: .telemetrySessionId)
        self.policy = try container.decode(BridgeTelemetryWorkerPolicy.self, forKey: .policy)
        try validate(codingPath: decoder.codingPath)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        guard enabledScopes == [.web] else {
            throw BridgeTelemetryContractValidation.invalidValue(
                "Invalid Bridge telemetry scopes",
                codingPath: codingPath
            )
        }
        guard !endpointUrl.isEmpty, endpointUrl.utf8.count <= 512 else {
            throw BridgeTelemetryContractValidation.invalidValue(
                "Invalid Bridge telemetry endpoint",
                codingPath: codingPath
            )
        }
        try BridgeTelemetryContractValidation.validateCapability(telemetryCapability, codingPath: codingPath)
        try BridgeTelemetryContractValidation.validateCapability(telemetryCapabilityDigest, codingPath: codingPath)
        try BridgeTelemetryContractValidation.validateIdentifier(telemetrySessionId, codingPath: codingPath)
        try policy.validate(codingPath: codingPath)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case enabledScopes
        case endpointUrl
        case telemetryCapability
        case telemetryCapabilityDigest
        case telemetrySessionId
        case policy
    }
}

enum BridgeTelemetryContractValidation {
    static func rejectUnknownKeys(
        from decoder: Decoder,
        allowedKeys: Set<String>,
        contract: String
    ) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: allowedKeys,
            contract: contract
        )
    }

    static func validateIdentifier(_ value: String, codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validateIdentifier(value, codingPath: codingPath)
    }

    static func validateCapability(_ value: String, codingPath: [any CodingKey]) throws {
        let allowedCharacters = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-"
        )
        guard
            value.utf8.count >= 24,
            value.utf8.count <= 256,
            value.unicodeScalars.allSatisfy(allowedCharacters.contains)
        else {
            throw invalidValue("Invalid Bridge telemetry capability", codingPath: codingPath)
        }
    }

    static func validatePositive(_ value: Int, codingPath: [any CodingKey]) throws {
        guard value > 0 else {
            throw invalidValue("Expected a positive integer", codingPath: codingPath)
        }
    }

    static func validateNonnegativeFinite(_ value: Double, codingPath: [any CodingKey]) throws {
        guard value.isFinite, value >= 0 else {
            throw invalidValue("Expected a finite nonnegative number", codingPath: codingPath)
        }
    }

    static func invalidValue(_ description: String, codingPath: [any CodingKey]) -> DecodingError {
        .dataCorrupted(.init(codingPath: codingPath, debugDescription: description))
    }
}
