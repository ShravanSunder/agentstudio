import Foundation

struct BridgeProductBootstrapPolicy: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case maximumContentBytes
        case maximumRequestBodyBytes
        case maximumMetadataFrameBytes
        case maximumQueuedStreamBytes
        case maximumQueuedStreamFrames
        case terminalFrameReserve
    }

    let maximumContentBytes: Int
    let maximumRequestBodyBytes: Int
    let maximumMetadataFrameBytes: Int
    let maximumQueuedStreamBytes: Int
    let maximumQueuedStreamFrames: Int
    let terminalFrameReserve: Int

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge product bootstrap policy"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.maximumContentBytes = try container.decode(Int.self, forKey: .maximumContentBytes)
        self.maximumRequestBodyBytes = try container.decode(Int.self, forKey: .maximumRequestBodyBytes)
        self.maximumMetadataFrameBytes = try container.decode(Int.self, forKey: .maximumMetadataFrameBytes)
        self.maximumQueuedStreamBytes = try container.decode(Int.self, forKey: .maximumQueuedStreamBytes)
        self.maximumQueuedStreamFrames = try container.decode(Int.self, forKey: .maximumQueuedStreamFrames)
        self.terminalFrameReserve = try container.decode(Int.self, forKey: .terminalFrameReserve)

        try validate(
            maximumContentBytes,
            maximum: BridgeProductWireContract.maximumContentBytes,
            name: "maximumContentBytes",
            codingPath: decoder.codingPath
        )
        try validate(
            maximumRequestBodyBytes,
            maximum: BridgeProductWireContract.maximumRequestBodyBytes,
            name: "maximumRequestBodyBytes",
            codingPath: decoder.codingPath
        )
        try validate(
            maximumMetadataFrameBytes,
            maximum: BridgeProductWireContract.maximumMetadataFrameBytes,
            name: "maximumMetadataFrameBytes",
            codingPath: decoder.codingPath
        )
        try validate(
            maximumQueuedStreamBytes,
            maximum: BridgeProductWireContract.maximumQueuedStreamBytes,
            name: "maximumQueuedStreamBytes",
            codingPath: decoder.codingPath
        )
        try validate(
            maximumQueuedStreamFrames,
            maximum: BridgeProductWireContract.maximumQueuedStreamFrames,
            name: "maximumQueuedStreamFrames",
            codingPath: decoder.codingPath
        )
        guard terminalFrameReserve == BridgeProductWireContract.terminalFrameReserve else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product policy must reserve exactly one terminal frame",
                codingPath: decoder.codingPath
            )
        }
    }

    private func validate(
        _ value: Int,
        maximum: Int,
        name: String,
        codingPath: [any CodingKey]
    ) throws {
        try BridgeProductContractDecoding.validatePositive(value, name: name, codingPath: codingPath)
        try BridgeProductContractDecoding.validateMaximum(
            value,
            maximum: maximum,
            name: name,
            codingPath: codingPath
        )
    }
}

struct BridgeProductSessionBootstrap: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case paneSessionId
        case policy
        case wireVersion
        case workerInstanceId
    }

    let paneSessionId: String
    let policy: BridgeProductBootstrapPolicy
    let wireVersion: Int
    let workerInstanceId: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge product session bootstrap"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "productSession.bootstrap" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Bridge product bootstrap kind",
                codingPath: decoder.codingPath
            )
        }
        self.paneSessionId = try container.decode(String.self, forKey: .paneSessionId)
        self.policy = try container.decode(BridgeProductBootstrapPolicy.self, forKey: .policy)
        self.wireVersion = try container.decode(Int.self, forKey: .wireVersion)
        self.workerInstanceId = try container.decode(String.self, forKey: .workerInstanceId)
        try BridgeProductContractDecoding.validateIdentifier(paneSessionId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateWireVersion(wireVersion, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(workerInstanceId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("productSession.bootstrap", forKey: .kind)
        try container.encode(paneSessionId, forKey: .paneSessionId)
        try container.encode(policy, forKey: .policy)
        try container.encode(wireVersion, forKey: .wireVersion)
        try container.encode(workerInstanceId, forKey: .workerInstanceId)
    }
}

enum BridgeProductCapabilityHeaderEncoding {
    static func encode(_ capabilityBytes: [UInt8]) throws -> String {
        guard capabilityBytes.count == BridgeProductWireContract.capabilityByteLength else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product capability must contain exactly 32 bytes",
                codingPath: []
            )
        }
        return Data(capabilityBytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
