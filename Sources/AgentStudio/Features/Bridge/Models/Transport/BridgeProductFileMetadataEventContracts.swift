import Foundation

struct BridgeProductFileSourceAcceptedEvent: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case eventKind
        case source
    }

    let source: BridgeProductFileSourceIdentity

    init(source: BridgeProductFileSourceIdentity) {
        self.source = source
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "File source-accepted event"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .eventKind) == "file.sourceAccepted" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid File source-accepted event kind",
                codingPath: decoder.codingPath
            )
        }
        self.source = try container.decode(BridgeProductFileSourceIdentity.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("file.sourceAccepted", forKey: .eventKind)
        try container.encode(source, forKey: .source)
    }
}

struct BridgeProductFileTreeWindowEvent: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case eventKind
        case finalWindow
        case lineage
        case pathScope
        case rows
        case source
        case startIndex
        case totalRowCount
    }

    let finalWindow: Bool
    let lineage: BridgeProductFileMetadataLineage
    let pathScope: [String]
    let rows: [BridgeProductFileTreeRow]
    let source: BridgeProductFileSourceIdentity
    let startIndex: Int
    let totalRowCount: Int?

    init(
        finalWindow: Bool,
        lineage: BridgeProductFileMetadataLineage,
        pathScope: [String],
        rows: [BridgeProductFileTreeRow],
        source: BridgeProductFileSourceIdentity,
        startIndex: Int,
        totalRowCount: Int?
    ) throws {
        self.finalWindow = finalWindow
        self.lineage = lineage
        self.pathScope = pathScope
        self.rows = rows
        self.source = source
        self.startIndex = startIndex
        self.totalRowCount = totalRowCount
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "File tree-window event"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .eventKind) == "file.treeWindow" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid File tree-window event kind",
                codingPath: decoder.codingPath
            )
        }
        self.finalWindow = try container.decode(Bool.self, forKey: .finalWindow)
        self.lineage = try container.decode(BridgeProductFileMetadataLineage.self, forKey: .lineage)
        self.pathScope = try container.decode([String].self, forKey: .pathScope)
        self.rows = try container.decode([BridgeProductFileTreeRow].self, forKey: .rows)
        self.source = try container.decode(BridgeProductFileSourceIdentity.self, forKey: .source)
        self.startIndex = try container.decode(Int.self, forKey: .startIndex)
        self.totalRowCount = try BridgeProductContractDecoding.decodeRequiredNullable(
            Int.self,
            forKey: .totalRowCount,
            from: container,
            codingPath: decoder.codingPath
        )
        try validate(codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("file.treeWindow", forKey: .eventKind)
        try container.encode(finalWindow, forKey: .finalWindow)
        try container.encode(lineage, forKey: .lineage)
        try container.encode(pathScope, forKey: .pathScope)
        try container.encode(rows, forKey: .rows)
        try container.encode(source, forKey: .source)
        try container.encode(startIndex, forKey: .startIndex)
        try container.encode(totalRowCount, forKey: .totalRowCount)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validateMaximum(
            pathScope.count,
            maximum: BridgeProductWireContract.maximumFileMetadataTreeWindowRowCount,
            name: "File metadata path-scope count",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            rows.count,
            maximum: BridgeProductWireContract.maximumFileMetadataTreeWindowRowCount,
            name: "File metadata tree-window row count",
            codingPath: codingPath
        )
        for path in pathScope {
            try BridgeProductContractDecoding.validateDisplayPath(path, codingPath: codingPath)
        }
        try BridgeProductContractDecoding.validateNonnegative(
            startIndex,
            name: "startIndex",
            codingPath: codingPath
        )
        if let totalRowCount {
            try BridgeProductContractDecoding.validateNonnegative(
                totalRowCount,
                name: "totalRowCount",
                codingPath: codingPath
            )
        }
    }
}

struct BridgeProductFileTreeDeltaEvent: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case eventKind
        case operations
        case source
    }

    let operations: [BridgeProductFileTreeOperation]
    let source: BridgeProductFileSourceIdentity

    init(operations: [BridgeProductFileTreeOperation], source: BridgeProductFileSourceIdentity) throws {
        self.operations = operations
        self.source = source
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "File tree-delta event"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .eventKind) == "file.treeDelta" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid File tree-delta event kind",
                codingPath: decoder.codingPath
            )
        }
        self.operations = try container.decode([BridgeProductFileTreeOperation].self, forKey: .operations)
        self.source = try container.decode(BridgeProductFileSourceIdentity.self, forKey: .source)
        try validate(codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("file.treeDelta", forKey: .eventKind)
        try container.encode(operations, forKey: .operations)
        try container.encode(source, forKey: .source)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validateMaximum(
            operations.count,
            maximum: BridgeProductWireContract.maximumFileMetadataOperationCount,
            name: "File metadata tree operation count",
            codingPath: codingPath
        )
        let aggregateMemberCount = operations.reduce(0) { $0 + $1.memberCount }
        try BridgeProductContractDecoding.validateMaximum(
            aggregateMemberCount,
            maximum: BridgeProductWireContract.maximumFileMetadataDeltaMemberCount,
            name: "File metadata tree-delta member count",
            codingPath: codingPath
        )
    }
}

struct BridgeProductFileStatusPatchEvent: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case eventKind
        case patch
        case source
    }

    let patch: BridgeProductFileStatusPatch
    let source: BridgeProductFileSourceIdentity

    init(patch: BridgeProductFileStatusPatch, source: BridgeProductFileSourceIdentity) {
        self.patch = patch
        self.source = source
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "File status-patch event"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .eventKind) == "file.statusPatch" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid File status-patch event kind",
                codingPath: decoder.codingPath
            )
        }
        self.patch = try container.decode(BridgeProductFileStatusPatch.self, forKey: .patch)
        self.source = try container.decode(BridgeProductFileSourceIdentity.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("file.statusPatch", forKey: .eventKind)
        try container.encode(patch, forKey: .patch)
        try container.encode(source, forKey: .source)
    }
}

struct BridgeProductFileDescriptorReadyEvent: Codable, Equatable, Sendable {
    private enum EventCodingKeys: String, CodingKey {
        case eventKind
    }

    let payload: BridgeProductFileDescriptorReadyPayload

    init(payload: BridgeProductFileDescriptorReadyPayload) {
        self.payload = payload
    }

    init(from decoder: Decoder) throws {
        let eventContainer = try decoder.container(keyedBy: EventCodingKeys.self)
        guard try eventContainer.decode(String.self, forKey: .eventKind) == "file.descriptorReady" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid File descriptor-ready event kind",
                codingPath: decoder.codingPath
            )
        }
        self.payload = try BridgeProductFileDescriptorReadyPayload(
            from: decoder,
            additionalAllowedKeys: [EventCodingKeys.eventKind.rawValue]
        )
    }

    func encode(to encoder: Encoder) throws {
        try payload.encode(to: encoder)
        var eventContainer = encoder.container(keyedBy: EventCodingKeys.self)
        try eventContainer.encode("file.descriptorReady", forKey: .eventKind)
    }
}

struct BridgeProductFileInvalidatedEvent: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case eventKind
        case fileId
        case path
        case reason
        case replacementDescriptor
        case source
    }

    let fileId: String?
    let path: String
    let reason: BridgeProductFileInvalidationReason
    let replacementDescriptor: BridgeProductFileDescriptorReadyPayload?
    let source: BridgeProductFileSourceIdentity

    init(
        fileId: String?,
        path: String,
        reason: BridgeProductFileInvalidationReason,
        replacementDescriptor: BridgeProductFileDescriptorReadyPayload?,
        source: BridgeProductFileSourceIdentity
    ) throws {
        self.fileId = fileId
        self.path = path
        self.reason = reason
        self.replacementDescriptor = replacementDescriptor
        self.source = source
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "File invalidated event"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .eventKind) == "file.invalidated" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid File invalidated event kind",
                codingPath: decoder.codingPath
            )
        }
        self.fileId = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .fileId,
            from: container,
            codingPath: decoder.codingPath
        )
        self.path = try container.decode(String.self, forKey: .path)
        self.reason = try container.decode(BridgeProductFileInvalidationReason.self, forKey: .reason)
        self.replacementDescriptor = try BridgeProductContractDecoding.decodeRequiredNullable(
            BridgeProductFileDescriptorReadyPayload.self,
            forKey: .replacementDescriptor,
            from: container,
            codingPath: decoder.codingPath
        )
        self.source = try container.decode(BridgeProductFileSourceIdentity.self, forKey: .source)
        try validate(codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("file.invalidated", forKey: .eventKind)
        try container.encode(fileId, forKey: .fileId)
        try container.encode(path, forKey: .path)
        try container.encode(reason, forKey: .reason)
        try container.encode(replacementDescriptor, forKey: .replacementDescriptor)
        try container.encode(source, forKey: .source)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        if let fileId {
            try BridgeProductContractDecoding.validateIdentifier(fileId, codingPath: codingPath)
        }
        try BridgeProductContractDecoding.validateDisplayPath(path, codingPath: codingPath)
    }
}

enum BridgeProductFileMetadataEvent: Codable, Equatable, Sendable {
    case sourceAccepted(BridgeProductFileSourceAcceptedEvent)
    case treeWindow(BridgeProductFileTreeWindowEvent)
    case treeDelta(BridgeProductFileTreeDeltaEvent)
    case statusPatch(BridgeProductFileStatusPatchEvent)
    case descriptorReady(BridgeProductFileDescriptorReadyEvent)
    case invalidated(BridgeProductFileInvalidatedEvent)

    private enum CodingKeys: String, CodingKey {
        case eventKind
    }

    var sourceGeneration: Int {
        switch self {
        case .sourceAccepted(let event): event.source.subscriptionGeneration
        case .treeWindow(let event): event.source.subscriptionGeneration
        case .treeDelta(let event): event.source.subscriptionGeneration
        case .statusPatch(let event): event.source.subscriptionGeneration
        case .descriptorReady(let event): event.payload.source.subscriptionGeneration
        case .invalidated(let event): event.source.subscriptionGeneration
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .eventKind) {
        case "file.sourceAccepted":
            self = .sourceAccepted(try BridgeProductFileSourceAcceptedEvent(from: decoder))
        case "file.treeWindow":
            self = .treeWindow(try BridgeProductFileTreeWindowEvent(from: decoder))
        case "file.treeDelta":
            self = .treeDelta(try BridgeProductFileTreeDeltaEvent(from: decoder))
        case "file.statusPatch":
            self = .statusPatch(try BridgeProductFileStatusPatchEvent(from: decoder))
        case "file.descriptorReady":
            self = .descriptorReady(try BridgeProductFileDescriptorReadyEvent(from: decoder))
        case "file.invalidated":
            self = .invalidated(try BridgeProductFileInvalidatedEvent(from: decoder))
        default:
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid File metadata event kind",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .sourceAccepted(let event): try event.encode(to: encoder)
        case .treeWindow(let event): try event.encode(to: encoder)
        case .treeDelta(let event): try event.encode(to: encoder)
        case .statusPatch(let event): try event.encode(to: encoder)
        case .descriptorReady(let event): try event.encode(to: encoder)
        case .invalidated(let event): try event.encode(to: encoder)
        }
    }
}
