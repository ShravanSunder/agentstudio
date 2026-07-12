import Foundation

enum BridgeProductReviewMetadataLoadedBy: String, Codable, Equatable, Sendable {
    case startupWindow = "startup_window"
    case foreground
    case visible
    case nearby
    case speculative
    case idle
    case delta
    case reset
    case replacement
}

struct BridgeProductReviewDescriptorIdsByRole: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case base
        case diff
        case file
        case head
    }

    let base: String?
    let diff: String?
    let file: String?
    let head: String?

    init(base: String?, diff: String?, file: String?, head: String?) throws {
        self.base = base
        self.diff = diff
        self.file = file
        self.head = head
        for value in [base, diff, file, head].compactMap({ $0 }) {
            try BridgeProductContractDecoding.validateIdentifier(value, codingPath: [])
        }
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review content descriptor role map"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.base = try container.decodeIfPresent(String.self, forKey: .base)
        self.diff = try container.decodeIfPresent(String.self, forKey: .diff)
        self.file = try container.decodeIfPresent(String.self, forKey: .file)
        self.head = try container.decodeIfPresent(String.self, forKey: .head)
        for value in [base, diff, file, head].compactMap({ $0 }) {
            try BridgeProductContractDecoding.validateIdentifier(value, codingPath: decoder.codingPath)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(base, forKey: .base)
        try container.encodeIfPresent(diff, forKey: .diff)
        try container.encodeIfPresent(file, forKey: .file)
        try container.encodeIfPresent(head, forKey: .head)
    }
}

struct BridgeProductReviewContentHashesByRole: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case base
        case diff
        case file
        case head
    }

    let base: String?
    let diff: String?
    let file: String?
    let head: String?

    init(base: String?, diff: String?, file: String?, head: String?) throws {
        self.base = base
        self.diff = diff
        self.file = file
        self.head = head
        for value in [base, diff, file, head].compactMap({ $0 }) {
            try BridgeProductContractDecoding.validateOpaqueReference(value, codingPath: [])
        }
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review content hash role map"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.base = try container.decodeIfPresent(String.self, forKey: .base)
        self.diff = try container.decodeIfPresent(String.self, forKey: .diff)
        self.file = try container.decodeIfPresent(String.self, forKey: .file)
        self.head = try container.decodeIfPresent(String.self, forKey: .head)
        for value in [base, diff, file, head].compactMap({ $0 }) {
            try BridgeProductContractDecoding.validateOpaqueReference(value, codingPath: decoder.codingPath)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(base, forKey: .base)
        try container.encodeIfPresent(diff, forKey: .diff)
        try container.encodeIfPresent(file, forKey: .file)
        try container.encodeIfPresent(head, forKey: .head)
    }
}

struct BridgeProductReviewItemProvenanceValue: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case agentSessionIds
        case operationIds
        case promptIds
    }

    let agentSessionIds: [String]
    let operationIds: [String]
    let promptIds: [String]

    init(agentSessionIds: [String], operationIds: [String], promptIds: [String]) throws {
        self.agentSessionIds = agentSessionIds
        self.operationIds = operationIds
        self.promptIds = promptIds
        for (values, name) in [
            (agentSessionIds, "agentSessionIds"),
            (operationIds, "operationIds"),
            (promptIds, "promptIds"),
        ] {
            try BridgeProductContractDecoding.validateCollectionCount(
                values.count,
                maximum: BridgeProductReviewMetadataLimits.maximumWindowEntryCount,
                name: name,
                codingPath: []
            )
            for value in values {
                try BridgeProductContractDecoding.validateIdentifier(value, codingPath: [])
            }
        }
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review item provenance"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.agentSessionIds = try container.decode([String].self, forKey: .agentSessionIds)
        self.operationIds = try container.decode([String].self, forKey: .operationIds)
        self.promptIds = try container.decode([String].self, forKey: .promptIds)
        for (values, name) in [
            (agentSessionIds, "agentSessionIds"),
            (operationIds, "operationIds"),
            (promptIds, "promptIds"),
        ] {
            try BridgeProductContractDecoding.validateCollectionCount(
                values.count,
                maximum: BridgeProductReviewMetadataLimits.maximumWindowEntryCount,
                name: name,
                codingPath: decoder.codingPath
            )
            for value in values {
                try BridgeProductContractDecoding.validateIdentifier(value, codingPath: decoder.codingPath)
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(agentSessionIds, forKey: .agentSessionIds)
        try container.encode(operationIds, forKey: .operationIds)
        try container.encode(promptIds, forKey: .promptIds)
    }
}

struct BridgeProductReviewItemMetadataValue: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case basePath
        case changeKind
        case contentDescriptorIdsByRole
        case contentHashesByRole
        case contentRoles
        case `extension`
        case fileClass
        case headPath
        case isHiddenByDefault
        case itemId
        case lane
        case language
        case loadedBy
        case mimeTypes
        case provenance
        case reviewPriority
        case reviewState
    }

    let basePath: String?
    let changeKind: BridgeFileChangeKind
    let contentDescriptorIdsByRole: BridgeProductReviewDescriptorIdsByRole
    let contentHashesByRole: BridgeProductReviewContentHashesByRole
    let contentRoles: [BridgeContentHandle.Role]
    let fileExtension: String?
    let fileClass: BridgeFileClass
    let headPath: String?
    let isHiddenByDefault: Bool
    let itemId: String
    let lane: BridgeProductDemandLane?
    let language: String?
    let loadedBy: BridgeProductReviewMetadataLoadedBy?
    let mimeTypes: [String]
    let provenance: BridgeProductReviewItemProvenanceValue
    let reviewPriority: BridgeReviewPriority
    let reviewState: BridgeFileReviewState

    init(
        basePath: String?,
        changeKind: BridgeFileChangeKind,
        contentDescriptorIdsByRole: BridgeProductReviewDescriptorIdsByRole,
        contentHashesByRole: BridgeProductReviewContentHashesByRole,
        contentRoles: [BridgeContentHandle.Role],
        fileExtension: String?,
        fileClass: BridgeFileClass,
        headPath: String?,
        isHiddenByDefault: Bool,
        itemId: String,
        lane: BridgeProductDemandLane?,
        language: String?,
        loadedBy: BridgeProductReviewMetadataLoadedBy?,
        mimeTypes: [String],
        provenance: BridgeProductReviewItemProvenanceValue,
        reviewPriority: BridgeReviewPriority,
        reviewState: BridgeFileReviewState
    ) throws {
        self.basePath = basePath
        self.changeKind = changeKind
        self.contentDescriptorIdsByRole = contentDescriptorIdsByRole
        self.contentHashesByRole = contentHashesByRole
        self.contentRoles = contentRoles
        self.fileExtension = fileExtension
        self.fileClass = fileClass
        self.headPath = headPath
        self.isHiddenByDefault = isHiddenByDefault
        self.itemId = itemId
        self.lane = lane
        self.language = language
        self.loadedBy = loadedBy
        self.mimeTypes = mimeTypes
        self.provenance = provenance
        self.reviewPriority = reviewPriority
        self.reviewState = reviewState
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review item metadata"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.basePath = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .basePath,
            from: container,
            codingPath: decoder.codingPath
        )
        self.changeKind = try container.decode(BridgeFileChangeKind.self, forKey: .changeKind)
        self.contentDescriptorIdsByRole = try container.decode(
            BridgeProductReviewDescriptorIdsByRole.self,
            forKey: .contentDescriptorIdsByRole
        )
        self.contentHashesByRole = try container.decode(
            BridgeProductReviewContentHashesByRole.self,
            forKey: .contentHashesByRole
        )
        self.contentRoles = try container.decode([BridgeContentHandle.Role].self, forKey: .contentRoles)
        self.fileExtension = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .extension,
            from: container,
            codingPath: decoder.codingPath
        )
        self.fileClass = try container.decode(BridgeFileClass.self, forKey: .fileClass)
        self.headPath = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .headPath,
            from: container,
            codingPath: decoder.codingPath
        )
        self.isHiddenByDefault = try container.decode(Bool.self, forKey: .isHiddenByDefault)
        self.itemId = try container.decode(String.self, forKey: .itemId)
        self.lane = try container.decodeIfPresent(BridgeProductDemandLane.self, forKey: .lane)
        self.language = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .language,
            from: container,
            codingPath: decoder.codingPath
        )
        self.loadedBy = try container.decodeIfPresent(BridgeProductReviewMetadataLoadedBy.self, forKey: .loadedBy)
        self.mimeTypes = try container.decode([String].self, forKey: .mimeTypes)
        self.provenance = try container.decode(BridgeProductReviewItemProvenanceValue.self, forKey: .provenance)
        self.reviewPriority = try container.decode(BridgeReviewPriority.self, forKey: .reviewPriority)
        self.reviewState = try container.decode(BridgeFileReviewState.self, forKey: .reviewState)
        try validate(codingPath: decoder.codingPath)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        for path in [basePath, headPath].compactMap({ $0 }) {
            try BridgeProductContractDecoding.validateDisplayPath(path, codingPath: codingPath)
        }
        try BridgeProductContractDecoding.validateCollectionCount(
            contentRoles.count,
            maximum: 4,
            name: "contentRoles",
            codingPath: codingPath
        )
        guard Set(contentRoles).count == contentRoles.count else {
            throw BridgeProductContractDecoding.invalidValue(
                "Review content roles must be unique",
                codingPath: codingPath
            )
        }
        if let fileExtension {
            try BridgeProductContractDecoding.validateOpaqueReference(fileExtension, codingPath: codingPath)
        }
        try BridgeProductContractDecoding.validateIdentifier(itemId, codingPath: codingPath)
        if let language {
            try BridgeProductContractDecoding.validateOpaqueReference(language, codingPath: codingPath)
        }
        try BridgeProductContractDecoding.validateCollectionCount(
            mimeTypes.count,
            maximum: 4,
            name: "mimeTypes",
            codingPath: codingPath
        )
        for mimeType in mimeTypes {
            try BridgeProductContractDecoding.validateOpaqueReference(mimeType, codingPath: codingPath)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(basePath, forKey: .basePath)
        try container.encode(changeKind, forKey: .changeKind)
        try container.encode(contentDescriptorIdsByRole, forKey: .contentDescriptorIdsByRole)
        try container.encode(contentHashesByRole, forKey: .contentHashesByRole)
        try container.encode(contentRoles, forKey: .contentRoles)
        try container.encode(fileExtension, forKey: .extension)
        try container.encode(fileClass, forKey: .fileClass)
        try container.encode(headPath, forKey: .headPath)
        try container.encode(isHiddenByDefault, forKey: .isHiddenByDefault)
        try container.encode(itemId, forKey: .itemId)
        try container.encodeIfPresent(lane, forKey: .lane)
        try container.encode(language, forKey: .language)
        try container.encodeIfPresent(loadedBy, forKey: .loadedBy)
        try container.encode(mimeTypes, forKey: .mimeTypes)
        try container.encode(provenance, forKey: .provenance)
        try container.encode(reviewPriority, forKey: .reviewPriority)
        try container.encode(reviewState, forKey: .reviewState)
    }
}

struct BridgeProductReviewTreeRowValue: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case depth
        case isDirectory
        case itemId
        case lane
        case loadedBy
        case path
        case rowId
    }

    let depth: Int
    let isDirectory: Bool
    let itemId: String?
    let lane: BridgeProductDemandLane?
    let loadedBy: BridgeProductReviewMetadataLoadedBy?
    let path: String
    let rowId: String

    init(
        depth: Int,
        isDirectory: Bool,
        itemId: String?,
        lane: BridgeProductDemandLane?,
        loadedBy: BridgeProductReviewMetadataLoadedBy?,
        path: String,
        rowId: String
    ) throws {
        self.depth = depth
        self.isDirectory = isDirectory
        self.itemId = itemId
        self.lane = lane
        self.loadedBy = loadedBy
        self.path = path
        self.rowId = rowId
        try BridgeProductContractDecoding.validateNonnegative(depth, name: "depth", codingPath: [])
        if let itemId {
            try BridgeProductContractDecoding.validateIdentifier(itemId, codingPath: [])
        }
        try BridgeProductContractDecoding.validateDisplayPath(path, codingPath: [])
        try BridgeProductContractDecoding.validateIdentifier(rowId, codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review tree row"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.depth = try container.decode(Int.self, forKey: .depth)
        self.isDirectory = try container.decode(Bool.self, forKey: .isDirectory)
        self.itemId = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .itemId,
            from: container,
            codingPath: decoder.codingPath
        )
        self.lane = try container.decodeIfPresent(BridgeProductDemandLane.self, forKey: .lane)
        self.loadedBy = try container.decodeIfPresent(BridgeProductReviewMetadataLoadedBy.self, forKey: .loadedBy)
        self.path = try container.decode(String.self, forKey: .path)
        self.rowId = try container.decode(String.self, forKey: .rowId)
        try BridgeProductContractDecoding.validateNonnegative(depth, name: "depth", codingPath: decoder.codingPath)
        if let itemId {
            try BridgeProductContractDecoding.validateIdentifier(itemId, codingPath: decoder.codingPath)
        }
        try BridgeProductContractDecoding.validateDisplayPath(path, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(rowId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(depth, forKey: .depth)
        try container.encode(isDirectory, forKey: .isDirectory)
        try container.encode(itemId, forKey: .itemId)
        try container.encodeIfPresent(lane, forKey: .lane)
        try container.encodeIfPresent(loadedBy, forKey: .loadedBy)
        try container.encode(path, forKey: .path)
        try container.encode(rowId, forKey: .rowId)
    }
}

struct BridgeProductReviewExtentFactValue: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contentRole
        case itemId
        case lineCount
    }

    let contentRole: BridgeContentHandle.Role
    let itemId: String
    let lineCount: Int

    init(contentRole: BridgeContentHandle.Role, itemId: String, lineCount: Int) throws {
        self.contentRole = contentRole
        self.itemId = itemId
        self.lineCount = lineCount
        try BridgeProductContractDecoding.validateIdentifier(itemId, codingPath: [])
        try BridgeProductContractDecoding.validateNonnegative(lineCount, name: "lineCount", codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review extent fact"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.contentRole = try container.decode(BridgeContentHandle.Role.self, forKey: .contentRole)
        self.itemId = try container.decode(String.self, forKey: .itemId)
        self.lineCount = try container.decode(Int.self, forKey: .lineCount)
        try BridgeProductContractDecoding.validateIdentifier(itemId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            lineCount,
            name: "lineCount",
            codingPath: decoder.codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contentRole, forKey: .contentRole)
        try container.encode(itemId, forKey: .itemId)
        try container.encode(lineCount, forKey: .lineCount)
    }
}
