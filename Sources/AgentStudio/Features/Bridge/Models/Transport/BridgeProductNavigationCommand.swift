import Foundation

enum BridgeProductNavigationFileVersion: String, Codable, Equatable, Sendable {
    case base
    case head
    case current
}

struct BridgeProductNavigationFileSource: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceId
        case sourceKind
        case subscriptionGeneration
    }

    let sourceId: String
    let subscriptionGeneration: Int

    init(sourceId: String, subscriptionGeneration: Int) {
        self.sourceId = sourceId
        self.subscriptionGeneration = subscriptionGeneration
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "file navigation source"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .sourceKind) == "file" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid file navigation source kind",
                codingPath: decoder.codingPath
            )
        }
        sourceId = try container.decode(String.self, forKey: .sourceId)
        subscriptionGeneration = try container.decode(Int.self, forKey: .subscriptionGeneration)
        try BridgeProductContractDecoding.validateIdentifier(sourceId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            subscriptionGeneration,
            name: "subscriptionGeneration",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            subscriptionGeneration,
            maximum: BridgeProductWireContract.maximumSafeInteger,
            name: "subscriptionGeneration",
            codingPath: decoder.codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        try BridgeProductContractDecoding.validateIdentifier(sourceId, codingPath: encoder.codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            subscriptionGeneration,
            name: "subscriptionGeneration",
            codingPath: encoder.codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            subscriptionGeneration,
            maximum: BridgeProductWireContract.maximumSafeInteger,
            name: "subscriptionGeneration",
            codingPath: encoder.codingPath
        )
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceId, forKey: .sourceId)
        try container.encode("file", forKey: .sourceKind)
        try container.encode(subscriptionGeneration, forKey: .subscriptionGeneration)
    }
}

struct BridgeProductNavigationReviewSource: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case generation
        case metadataSourceId
        case packageId
        case sourceKind
    }

    let generation: Int
    let metadataSourceId: String
    let packageId: String

    init(generation: Int, metadataSourceId: String, packageId: String) {
        self.generation = generation
        self.metadataSourceId = metadataSourceId
        self.packageId = packageId
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review navigation source"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .sourceKind) == "review" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Review navigation source kind",
                codingPath: decoder.codingPath
            )
        }
        generation = try container.decode(Int.self, forKey: .generation)
        metadataSourceId = try container.decode(String.self, forKey: .metadataSourceId)
        packageId = try container.decode(String.self, forKey: .packageId)
        try BridgeProductContractDecoding.validateNonnegative(
            generation,
            name: "generation",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            generation,
            maximum: BridgeProductWireContract.maximumSafeInteger,
            name: "generation",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(
            metadataSourceId,
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(packageId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try BridgeProductContractDecoding.validateNonnegative(
            generation,
            name: "generation",
            codingPath: encoder.codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            generation,
            maximum: BridgeProductWireContract.maximumSafeInteger,
            name: "generation",
            codingPath: encoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(
            metadataSourceId,
            codingPath: encoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(packageId, codingPath: encoder.codingPath)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(generation, forKey: .generation)
        try container.encode(metadataSourceId, forKey: .metadataSourceId)
        try container.encode(packageId, forKey: .packageId)
        try container.encode("review", forKey: .sourceKind)
    }
}

struct BridgeProductNavigationFileTarget: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case path
        case targetKind
        case version
    }

    let path: String
    let version: BridgeProductNavigationFileVersion

    init(path: String, version: BridgeProductNavigationFileVersion) {
        self.path = path
        self.version = version
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "file navigation target"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .targetKind) == "file" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid file navigation target kind",
                codingPath: decoder.codingPath
            )
        }
        path = try container.decode(String.self, forKey: .path)
        version = try container.decode(BridgeProductNavigationFileVersion.self, forKey: .version)
        try Self.validatePath(path, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try Self.validatePath(path, codingPath: encoder.codingPath)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode("file", forKey: .targetKind)
        try container.encode(version, forKey: .version)
    }

    fileprivate static func validatePath(_ path: String, codingPath: [any CodingKey]) throws {
        guard !path.isEmpty else {
            throw BridgeProductContractDecoding.invalidValue(
                "Navigation path must not be empty",
                codingPath: codingPath
            )
        }
    }
}

struct BridgeProductNavigationReviewTarget: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case path
        case reviewItemId
        case targetKind
        case version
    }

    let path: String?
    let reviewItemId: String?
    let version: BridgeProductNavigationFileVersion?

    init(
        path: String? = nil,
        reviewItemId: String? = nil,
        version: BridgeProductNavigationFileVersion? = nil
    ) {
        self.path = path
        self.reviewItemId = reviewItemId
        self.version = version
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review navigation target"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .targetKind) == "review" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Review navigation target kind",
                codingPath: decoder.codingPath
            )
        }
        path = try container.decodeIfPresent(String.self, forKey: .path)
        reviewItemId = try container.decodeIfPresent(String.self, forKey: .reviewItemId)
        version = try container.decodeIfPresent(
            BridgeProductNavigationFileVersion.self,
            forKey: .version
        )
        try validate(codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try validate(codingPath: encoder.codingPath)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(path, forKey: .path)
        try container.encodeIfPresent(reviewItemId, forKey: .reviewItemId)
        try container.encode("review", forKey: .targetKind)
        try container.encodeIfPresent(version, forKey: .version)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        guard path != nil || reviewItemId != nil else {
            throw BridgeProductContractDecoding.invalidValue(
                "Review navigation target requires an item or file path",
                codingPath: codingPath
            )
        }
        guard (path == nil) == (version == nil) else {
            throw BridgeProductContractDecoding.invalidValue(
                "Review navigation file path and version must be supplied together",
                codingPath: codingPath
            )
        }
        if let path {
            try BridgeProductNavigationFileTarget.validatePath(path, codingPath: codingPath)
        }
        if let reviewItemId {
            try BridgeProductContractDecoding.validateIdentifier(reviewItemId, codingPath: codingPath)
        }
    }
}

enum BridgeProductNavigationCommand: Codable, Equatable, Sendable {
    case activateContext(commandId: String, bindingRevision: Int, surface: BridgeProductSurface)
    case activateFileTarget(
        commandId: String,
        bindingRevision: Int,
        source: BridgeProductNavigationFileSource,
        target: BridgeProductNavigationFileTarget
    )
    case activateReviewTarget(
        commandId: String,
        bindingRevision: Int,
        source: BridgeProductNavigationReviewSource,
        target: BridgeProductNavigationReviewTarget
    )

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case bindingRevision
        case commandId
        case commandKind
        case source
        case surface
        case target
    }

    var commandId: String {
        switch self {
        case .activateContext(let commandId, _, _),
            .activateFileTarget(let commandId, _, _, _),
            .activateReviewTarget(let commandId, _, _, _):
            commandId
        }
    }

    var bindingRevision: Int {
        switch self {
        case .activateContext(_, let bindingRevision, _),
            .activateFileTarget(_, let bindingRevision, _, _),
            .activateReviewTarget(_, let bindingRevision, _, _):
            bindingRevision
        }
    }

    var surface: BridgeProductSurface {
        switch self {
        case .activateContext(_, _, let surface): surface
        case .activateFileTarget: .file
        case .activateReviewTarget: .review
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let commandKind = try container.decode(String.self, forKey: .commandKind)
        let surface = try container.decode(BridgeProductSurface.self, forKey: .surface)
        let commandId = try container.decode(String.self, forKey: .commandId)
        let bindingRevision = try container.decode(Int.self, forKey: .bindingRevision)
        try BridgeProductContractDecoding.validateIdentifier(commandId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validatePositive(
            bindingRevision,
            name: "bindingRevision",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            bindingRevision,
            maximum: BridgeProductWireContract.maximumSafeInteger,
            name: "bindingRevision",
            codingPath: decoder.codingPath
        )

        switch (commandKind, surface) {
        case ("activateContext", let surface):
            try Self.rejectUnknownKeys(
                from: decoder,
                allowedKeys: [.bindingRevision, .commandId, .commandKind, .surface]
            )
            self = .activateContext(
                commandId: commandId,
                bindingRevision: bindingRevision,
                surface: surface
            )
        case ("activateTarget", .file):
            try Self.rejectUnknownKeys(from: decoder, allowedKeys: Set(CodingKeys.allCases))
            self = .activateFileTarget(
                commandId: commandId,
                bindingRevision: bindingRevision,
                source: try container.decode(BridgeProductNavigationFileSource.self, forKey: .source),
                target: try container.decode(BridgeProductNavigationFileTarget.self, forKey: .target)
            )
        case ("activateTarget", .review):
            try Self.rejectUnknownKeys(from: decoder, allowedKeys: Set(CodingKeys.allCases))
            self = .activateReviewTarget(
                commandId: commandId,
                bindingRevision: bindingRevision,
                source: try container.decode(BridgeProductNavigationReviewSource.self, forKey: .source),
                target: try container.decode(BridgeProductNavigationReviewTarget.self, forKey: .target)
            )
        default:
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Bridge product navigation command",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        try BridgeProductContractDecoding.validateIdentifier(commandId, codingPath: encoder.codingPath)
        try BridgeProductContractDecoding.validatePositive(
            bindingRevision,
            name: "bindingRevision",
            codingPath: encoder.codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            bindingRevision,
            maximum: BridgeProductWireContract.maximumSafeInteger,
            name: "bindingRevision",
            codingPath: encoder.codingPath
        )
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bindingRevision, forKey: .bindingRevision)
        try container.encode(commandId, forKey: .commandId)
        try container.encode(surface, forKey: .surface)
        switch self {
        case .activateContext:
            try container.encode("activateContext", forKey: .commandKind)
        case .activateFileTarget(_, _, let source, let target):
            try container.encode("activateTarget", forKey: .commandKind)
            try container.encode(source, forKey: .source)
            try container.encode(target, forKey: .target)
        case .activateReviewTarget(_, _, let source, let target):
            try container.encode("activateTarget", forKey: .commandKind)
            try container.encode(source, forKey: .source)
            try container.encode(target, forKey: .target)
        }
    }

    private static func rejectUnknownKeys(
        from decoder: Decoder,
        allowedKeys: Set<CodingKeys>
    ) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(allowedKeys.map(\.rawValue)),
            contract: "Bridge product navigation command"
        )
    }
}
