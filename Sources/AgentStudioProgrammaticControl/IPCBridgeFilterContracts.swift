import Foundation

public enum IPCBridgeFileTreeFilterSurface: String, Codable, Equatable, Sendable {
    case files
    case review
}

public enum IPCBridgeFilterCategory: String, Codable, Equatable, Sendable {
    case all
    case source
    case test
    case docs
    case config
    case generated
    case vendor
    case fixture
    case unknown
}

public enum IPCBridgeGitStatusFilter: String, Codable, Equatable, Sendable {
    case all
    case added
    case modified
    case deleted
    case renamed
    case copied
}

private struct IPCBridgeFilterCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

public enum IPCBridgeFileTreeFilterCandidate: Codable, Equatable, Sendable {
    case files(categoryFilter: IPCBridgeFilterCategory)
    case review(
        gitStatusFilter: IPCBridgeGitStatusFilter,
        categoryFilter: IPCBridgeFilterCategory,
        showBinary: Bool,
        showLarge: Bool
    )

    public var surface: IPCBridgeFileTreeFilterSurface {
        switch self {
        case .files:
            .files
        case .review:
            .review
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case surface
        case gitStatusFilter
        case categoryFilter
        case showBinary
        case showLarge
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let surface = try container.decode(IPCBridgeFileTreeFilterSurface.self, forKey: .surface)
        let allowedKeys: Set<String>
        switch surface {
        case .files:
            allowedKeys = [CodingKeys.surface.rawValue, CodingKeys.categoryFilter.rawValue]
        case .review:
            allowedKeys = Set(CodingKeys.allCases.map(\.rawValue))
        }
        let receivedKeys = try decoder.container(keyedBy: IPCBridgeFilterCodingKey.self).allKeys
        guard receivedKeys.allSatisfy({ allowedKeys.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Bridge filter candidates cannot carry undeclared fields"
                )
            )
        }

        switch surface {
        case .files:
            self = .files(
                categoryFilter: try container.decode(
                    IPCBridgeFilterCategory.self,
                    forKey: .categoryFilter
                )
            )
        case .review:
            self = .review(
                gitStatusFilter: try container.decode(
                    IPCBridgeGitStatusFilter.self,
                    forKey: .gitStatusFilter
                ),
                categoryFilter: try container.decode(
                    IPCBridgeFilterCategory.self,
                    forKey: .categoryFilter
                ),
                showBinary: try container.decode(Bool.self, forKey: .showBinary),
                showLarge: try container.decode(Bool.self, forKey: .showLarge)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(surface, forKey: .surface)
        switch self {
        case .files(let categoryFilter):
            try container.encode(categoryFilter, forKey: .categoryFilter)
        case .review(let gitStatusFilter, let categoryFilter, let showBinary, let showLarge):
            try container.encode(gitStatusFilter, forKey: .gitStatusFilter)
            try container.encode(categoryFilter, forKey: .categoryFilter)
            try container.encode(showBinary, forKey: .showBinary)
            try container.encode(showLarge, forKey: .showLarge)
        }
    }
}

public struct IPCBridgeFileTreeSetFilterParams: Codable, Equatable, Sendable {
    public let handle: String
    public let candidate: IPCBridgeFileTreeFilterCandidate
    public let correlationId: UUID?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case handle
        case candidate
        case correlationId
    }

    public init(
        handle: String,
        candidate: IPCBridgeFileTreeFilterCandidate,
        correlationId: UUID? = nil
    ) {
        self.handle = handle
        self.candidate = candidate
        self.correlationId = correlationId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let allowedKeys = Set(CodingKeys.allCases.map(\.rawValue))
        let receivedKeys = try decoder.container(keyedBy: IPCBridgeFilterCodingKey.self).allKeys
        guard receivedKeys.allSatisfy({ allowedKeys.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Bridge filter params cannot carry undeclared fields"
                )
            )
        }

        handle = try container.decode(String.self, forKey: .handle)
        candidate = try container.decode(IPCBridgeFileTreeFilterCandidate.self, forKey: .candidate)
        correlationId = try container.decodeIfPresent(UUID.self, forKey: .correlationId)
    }
}
