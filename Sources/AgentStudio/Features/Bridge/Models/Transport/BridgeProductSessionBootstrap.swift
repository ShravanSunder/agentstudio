import Foundation

enum BridgeProductResourceKind: String, Codable, Equatable, Sendable {
    case reviewContent = "review.content"
    case fileContent = "file.content"
}

struct BridgeProductBootstrapPolicy: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case maximumControlRequestBytes
        case maximumStreamFrameBytes
        case maximumQueuedStreamFrames
        case maximumQueuedStreamBytes
        case maximumResourceBytes
        case terminalFrameReserve
    }

    let maximumControlRequestBytes: Int
    let maximumStreamFrameBytes: Int
    let maximumQueuedStreamFrames: Int
    let maximumQueuedStreamBytes: Int
    let maximumResourceBytes: Int
    let terminalFrameReserve: Int

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge product bootstrap policy"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.maximumControlRequestBytes = try container.decode(Int.self, forKey: .maximumControlRequestBytes)
        self.maximumStreamFrameBytes = try container.decode(Int.self, forKey: .maximumStreamFrameBytes)
        self.maximumQueuedStreamFrames = try container.decode(Int.self, forKey: .maximumQueuedStreamFrames)
        self.maximumQueuedStreamBytes = try container.decode(Int.self, forKey: .maximumQueuedStreamBytes)
        self.maximumResourceBytes = try container.decode(Int.self, forKey: .maximumResourceBytes)
        self.terminalFrameReserve = try container.decode(Int.self, forKey: .terminalFrameReserve)

        try validate(
            maximumControlRequestBytes,
            maximum: BridgeProductWireContract.maximumControlRequestBytes,
            name: "maximumControlRequestBytes",
            codingPath: decoder.codingPath
        )
        try validate(
            maximumStreamFrameBytes,
            maximum: BridgeProductWireContract.maximumStreamFrameBytes,
            name: "maximumStreamFrameBytes",
            codingPath: decoder.codingPath
        )
        try validate(
            maximumQueuedStreamFrames,
            maximum: BridgeProductWireContract.maximumQueuedStreamFrames,
            name: "maximumQueuedStreamFrames",
            codingPath: decoder.codingPath
        )
        try validate(
            maximumQueuedStreamBytes,
            maximum: BridgeProductWireContract.maximumQueuedStreamBytes,
            name: "maximumQueuedStreamBytes",
            codingPath: decoder.codingPath
        )
        try validate(
            maximumResourceBytes,
            maximum: BridgeProductWireContract.maximumResourceBytes,
            name: "maximumResourceBytes",
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
        guard value <= maximum else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product \(name) exceeds the wire ceiling",
                codingPath: codingPath
            )
        }
    }
}

struct BridgeProductCommandRoute: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case method
        case url
    }

    let method: String
    let url: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge product command route"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.method = try container.decode(String.self, forKey: .method)
        self.url = try container.decode(String.self, forKey: .url)
        guard method == "POST", url == "agentstudio://rpc/command" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Bridge product command route",
                codingPath: decoder.codingPath
            )
        }
    }
}

struct BridgeProductStreamRoute: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case method
        case url
    }

    let method: String
    let url: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge product stream route"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.method = try container.decode(String.self, forKey: .method)
        self.url = try container.decode(String.self, forKey: .url)
        guard method == "POST", url == "agentstudio://rpc/stream" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Bridge product stream route",
                codingPath: decoder.codingPath
            )
        }
    }
}

struct BridgeProductResourceRoute: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case method
        case urlPrefix
    }

    let method: String
    let urlPrefix: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge product resource route"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.method = try container.decode(String.self, forKey: .method)
        self.urlPrefix = try container.decode(String.self, forKey: .urlPrefix)
        guard method == "GET", urlPrefix == "agentstudio://resource/" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Bridge product resource route",
                codingPath: decoder.codingPath
            )
        }
    }
}

struct BridgeProductRouteVocabulary: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case command
        case stream
        case resource
    }

    let command: BridgeProductCommandRoute
    let stream: BridgeProductStreamRoute
    let resource: BridgeProductResourceRoute

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge product route vocabulary"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.command = try container.decode(BridgeProductCommandRoute.self, forKey: .command)
        self.stream = try container.decode(BridgeProductStreamRoute.self, forKey: .stream)
        self.resource = try container.decode(BridgeProductResourceRoute.self, forKey: .resource)
    }
}

struct BridgeProductSessionBootstrap: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case wireVersion
        case paneSessionId
        case workerInstanceId
        case initialSurface
        case productCapabilityBytes
        case policy
        case routes
    }

    let kind: String
    let wireVersion: Int
    let paneSessionId: String
    let workerInstanceId: String
    let initialSurface: BridgeProductSurface
    let productCapabilityBytes: [UInt8]
    let policy: BridgeProductBootstrapPolicy
    let routes: BridgeProductRouteVocabulary

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge product session bootstrap"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decode(String.self, forKey: .kind)
        self.wireVersion = try container.decode(Int.self, forKey: .wireVersion)
        self.paneSessionId = try container.decode(String.self, forKey: .paneSessionId)
        self.workerInstanceId = try container.decode(String.self, forKey: .workerInstanceId)
        self.initialSurface = try container.decode(BridgeProductSurface.self, forKey: .initialSurface)
        self.productCapabilityBytes = try container.decode([UInt8].self, forKey: .productCapabilityBytes)
        self.policy = try container.decode(BridgeProductBootstrapPolicy.self, forKey: .policy)
        self.routes = try container.decode(BridgeProductRouteVocabulary.self, forKey: .routes)

        guard kind == "productSession.bootstrap" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Bridge product bootstrap kind",
                codingPath: decoder.codingPath
            )
        }
        try BridgeProductContractDecoding.validateWireVersion(wireVersion, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(paneSessionId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(workerInstanceId, codingPath: decoder.codingPath)
        guard productCapabilityBytes.count == BridgeProductWireContract.capabilityByteLength else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product capability must contain exactly 32 bytes",
                codingPath: decoder.codingPath
            )
        }
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
