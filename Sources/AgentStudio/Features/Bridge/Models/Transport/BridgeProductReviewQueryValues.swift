import Foundation

struct BridgeProductReviewViewFilterValue: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case changeKinds
        case excludedExtensions
        case excludedFileClasses
        case excludedPathGlobs
        case includedExtensions
        case includedFileClasses
        case includedPathGlobs
        case reviewStates
        case showBinaryFiles
        case showHiddenFiles
        case showLargeFiles
    }

    let changeKinds: [BridgeFileChangeKind]
    let excludedExtensions: [String]
    let excludedFileClasses: [BridgeFileClass]
    let excludedPathGlobs: [String]
    let includedExtensions: [String]
    let includedFileClasses: [BridgeFileClass]
    let includedPathGlobs: [String]
    let reviewStates: [BridgeFileReviewState]
    let showBinaryFiles: Bool
    let showHiddenFiles: Bool
    let showLargeFiles: Bool

    init(
        changeKinds: [BridgeFileChangeKind],
        excludedExtensions: [String],
        excludedFileClasses: [BridgeFileClass],
        excludedPathGlobs: [String],
        includedExtensions: [String],
        includedFileClasses: [BridgeFileClass],
        includedPathGlobs: [String],
        reviewStates: [BridgeFileReviewState],
        showBinaryFiles: Bool,
        showHiddenFiles: Bool,
        showLargeFiles: Bool
    ) throws {
        self.changeKinds = changeKinds
        self.excludedExtensions = excludedExtensions
        self.excludedFileClasses = excludedFileClasses
        self.excludedPathGlobs = excludedPathGlobs
        self.includedExtensions = includedExtensions
        self.includedFileClasses = includedFileClasses
        self.includedPathGlobs = includedPathGlobs
        self.reviewStates = reviewStates
        self.showBinaryFiles = showBinaryFiles
        self.showHiddenFiles = showHiddenFiles
        self.showLargeFiles = showLargeFiles
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review view filter"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.changeKinds = try container.decode([BridgeFileChangeKind].self, forKey: .changeKinds)
        self.excludedExtensions = try container.decode([String].self, forKey: .excludedExtensions)
        self.excludedFileClasses = try container.decode([BridgeFileClass].self, forKey: .excludedFileClasses)
        self.excludedPathGlobs = try container.decode([String].self, forKey: .excludedPathGlobs)
        self.includedExtensions = try container.decode([String].self, forKey: .includedExtensions)
        self.includedFileClasses = try container.decode([BridgeFileClass].self, forKey: .includedFileClasses)
        self.includedPathGlobs = try container.decode([String].self, forKey: .includedPathGlobs)
        self.reviewStates = try container.decode([BridgeFileReviewState].self, forKey: .reviewStates)
        self.showBinaryFiles = try container.decode(Bool.self, forKey: .showBinaryFiles)
        self.showHiddenFiles = try container.decode(Bool.self, forKey: .showHiddenFiles)
        self.showLargeFiles = try container.decode(Bool.self, forKey: .showLargeFiles)
        try validate(codingPath: decoder.codingPath)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validateCollectionCount(
            changeKinds.count,
            maximum: 5,
            name: "changeKinds",
            codingPath: codingPath
        )
        for (values, name) in [
            (excludedExtensions, "excludedExtensions"),
            (includedExtensions, "includedExtensions"),
        ] {
            try BridgeProductContractDecoding.validateCollectionCount(
                values.count,
                maximum: 256,
                name: name,
                codingPath: codingPath
            )
            for value in values {
                try BridgeProductContractDecoding.validateOpaqueReference(value, codingPath: codingPath)
            }
        }
        for (values, name) in [
            (excludedFileClasses, "excludedFileClasses"),
            (includedFileClasses, "includedFileClasses"),
        ] {
            try BridgeProductContractDecoding.validateCollectionCount(
                values.count,
                maximum: 10,
                name: name,
                codingPath: codingPath
            )
        }
        for (values, name) in [
            (excludedPathGlobs, "excludedPathGlobs"),
            (includedPathGlobs, "includedPathGlobs"),
        ] {
            try BridgeProductContractDecoding.validateCollectionCount(
                values.count,
                maximum: 256,
                name: name,
                codingPath: codingPath
            )
            for value in values {
                try BridgeProductContractDecoding.validateDisplayPath(value, codingPath: codingPath)
            }
        }
        try BridgeProductContractDecoding.validateCollectionCount(
            reviewStates.count,
            maximum: 4,
            name: "reviewStates",
            codingPath: codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(changeKinds, forKey: .changeKinds)
        try container.encode(excludedExtensions, forKey: .excludedExtensions)
        try container.encode(excludedFileClasses, forKey: .excludedFileClasses)
        try container.encode(excludedPathGlobs, forKey: .excludedPathGlobs)
        try container.encode(includedExtensions, forKey: .includedExtensions)
        try container.encode(includedFileClasses, forKey: .includedFileClasses)
        try container.encode(includedPathGlobs, forKey: .includedPathGlobs)
        try container.encode(reviewStates, forKey: .reviewStates)
        try container.encode(showBinaryFiles, forKey: .showBinaryFiles)
        try container.encode(showHiddenFiles, forKey: .showHiddenFiles)
        try container.encode(showLargeFiles, forKey: .showLargeFiles)
    }
}

struct BridgeProductReviewProvenanceFilterValue: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case agentSessionIds
        case createdAfterUnixMilliseconds
        case createdBeforeUnixMilliseconds
        case operationIds
        case paneIds
        case promptIds
        case sourceKinds
    }

    let agentSessionIds: [String]
    let createdAfterUnixMilliseconds: Int?
    let createdBeforeUnixMilliseconds: Int?
    let operationIds: [String]
    let paneIds: [String]
    let promptIds: [String]
    let sourceKinds: [String]

    init(
        agentSessionIds: [String],
        createdAfterUnixMilliseconds: Int?,
        createdBeforeUnixMilliseconds: Int?,
        operationIds: [String],
        paneIds: [String],
        promptIds: [String],
        sourceKinds: [String]
    ) throws {
        self.agentSessionIds = agentSessionIds
        self.createdAfterUnixMilliseconds = createdAfterUnixMilliseconds
        self.createdBeforeUnixMilliseconds = createdBeforeUnixMilliseconds
        self.operationIds = operationIds
        self.paneIds = paneIds
        self.promptIds = promptIds
        self.sourceKinds = sourceKinds
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review provenance filter"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.agentSessionIds = try container.decode([String].self, forKey: .agentSessionIds)
        self.createdAfterUnixMilliseconds = try container.decodeIfPresent(
            Int.self,
            forKey: .createdAfterUnixMilliseconds
        )
        self.createdBeforeUnixMilliseconds = try container.decodeIfPresent(
            Int.self,
            forKey: .createdBeforeUnixMilliseconds
        )
        self.operationIds = try container.decode([String].self, forKey: .operationIds)
        self.paneIds = try container.decode([String].self, forKey: .paneIds)
        self.promptIds = try container.decode([String].self, forKey: .promptIds)
        self.sourceKinds = try container.decode([String].self, forKey: .sourceKinds)
        try validate(codingPath: decoder.codingPath)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        for (values, name) in [
            (agentSessionIds, "agentSessionIds"),
            (operationIds, "operationIds"),
            (paneIds, "paneIds"),
            (promptIds, "promptIds"),
        ] {
            try BridgeProductContractDecoding.validateCollectionCount(
                values.count,
                maximum: BridgeProductReviewMetadataLimits.maximumProvenanceIdentityCount,
                name: name,
                codingPath: codingPath
            )
            for value in values {
                try BridgeProductContractDecoding.validateIdentifier(value, codingPath: codingPath)
            }
        }
        try BridgeProductContractDecoding.validateCollectionCount(
            sourceKinds.count,
            maximum: BridgeProductReviewMetadataLimits.maximumProvenanceSourceKindCount,
            name: "sourceKinds",
            codingPath: codingPath
        )
        for value in sourceKinds {
            try BridgeProductContractDecoding.validateOpaqueReference(value, codingPath: codingPath)
        }
        for (value, name) in [
            (createdAfterUnixMilliseconds, "createdAfterUnixMilliseconds"),
            (createdBeforeUnixMilliseconds, "createdBeforeUnixMilliseconds"),
        ] {
            if let value {
                try BridgeProductContractDecoding.validateNonnegative(value, name: name, codingPath: codingPath)
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(agentSessionIds, forKey: .agentSessionIds)
        try container.encodeIfPresent(createdAfterUnixMilliseconds, forKey: .createdAfterUnixMilliseconds)
        try container.encodeIfPresent(createdBeforeUnixMilliseconds, forKey: .createdBeforeUnixMilliseconds)
        try container.encode(operationIds, forKey: .operationIds)
        try container.encode(paneIds, forKey: .paneIds)
        try container.encode(promptIds, forKey: .promptIds)
        try container.encode(sourceKinds, forKey: .sourceKinds)
    }
}

struct BridgeProductReviewQueryValue: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case baseEndpointId
        case comparisonSemantics
        case fileTarget
        case grouping
        case headEndpointId
        case pathScope
        case provenanceFilter
        case queryId
        case queryKind
        case repoId
        case viewFilter
        case worktreeId
    }

    let baseEndpointId: String?
    let comparisonSemantics: BridgeReviewQuery.ComparisonSemantics
    let fileTarget: String?
    let grouping: BridgeProductReviewGroupingValue
    let headEndpointId: String?
    let pathScope: [String]
    let provenanceFilter: BridgeProductReviewProvenanceFilterValue
    let queryId: String
    let queryKind: BridgeReviewQuery.Kind
    let repoId: String
    let viewFilter: BridgeProductReviewViewFilterValue
    let worktreeId: String

    init(
        baseEndpointId: String?,
        comparisonSemantics: BridgeReviewQuery.ComparisonSemantics,
        fileTarget: String?,
        grouping: BridgeProductReviewGroupingValue,
        headEndpointId: String?,
        pathScope: [String],
        provenanceFilter: BridgeProductReviewProvenanceFilterValue,
        queryId: String,
        queryKind: BridgeReviewQuery.Kind,
        repoId: String,
        viewFilter: BridgeProductReviewViewFilterValue,
        worktreeId: String
    ) throws {
        self.baseEndpointId = baseEndpointId
        self.comparisonSemantics = comparisonSemantics
        self.fileTarget = fileTarget
        self.grouping = grouping
        self.headEndpointId = headEndpointId
        self.pathScope = pathScope
        self.provenanceFilter = provenanceFilter
        self.queryId = queryId
        self.queryKind = queryKind
        self.repoId = repoId
        self.viewFilter = viewFilter
        self.worktreeId = worktreeId
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review query"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.baseEndpointId = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .baseEndpointId,
            from: container,
            codingPath: decoder.codingPath
        )
        self.comparisonSemantics = try container.decode(
            BridgeReviewQuery.ComparisonSemantics.self,
            forKey: .comparisonSemantics
        )
        self.fileTarget = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .fileTarget,
            from: container,
            codingPath: decoder.codingPath
        )
        self.grouping = try container.decode(BridgeProductReviewGroupingValue.self, forKey: .grouping)
        self.headEndpointId = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .headEndpointId,
            from: container,
            codingPath: decoder.codingPath
        )
        self.pathScope = try container.decode([String].self, forKey: .pathScope)
        self.provenanceFilter = try container.decode(
            BridgeProductReviewProvenanceFilterValue.self,
            forKey: .provenanceFilter
        )
        self.queryId = try container.decode(String.self, forKey: .queryId)
        self.queryKind = try container.decode(BridgeReviewQuery.Kind.self, forKey: .queryKind)
        self.repoId = try container.decode(String.self, forKey: .repoId)
        self.viewFilter = try container.decode(BridgeProductReviewViewFilterValue.self, forKey: .viewFilter)
        self.worktreeId = try container.decode(String.self, forKey: .worktreeId)
        try validate(codingPath: decoder.codingPath)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        for value in [baseEndpointId, headEndpointId].compactMap({ $0 }) {
            try BridgeProductContractDecoding.validateIdentifier(value, codingPath: codingPath)
        }
        if let fileTarget {
            try BridgeProductContractDecoding.validateDisplayPath(fileTarget, codingPath: codingPath)
        }
        try BridgeProductContractDecoding.validateCollectionCount(
            pathScope.count,
            maximum: BridgeProductReviewMetadataLimits.maximumPathScopeCount,
            name: "pathScope",
            codingPath: codingPath
        )
        for path in pathScope {
            try BridgeProductContractDecoding.validateDisplayPath(path, codingPath: codingPath)
        }
        try BridgeProductContractDecoding.validateIdentifier(queryId, codingPath: codingPath)
        try BridgeProductContractDecoding.validateIdentifier(repoId, codingPath: codingPath)
        try BridgeProductContractDecoding.validateIdentifier(worktreeId, codingPath: codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(baseEndpointId, forKey: .baseEndpointId)
        try container.encode(comparisonSemantics, forKey: .comparisonSemantics)
        try container.encode(fileTarget, forKey: .fileTarget)
        try container.encode(grouping, forKey: .grouping)
        try container.encode(headEndpointId, forKey: .headEndpointId)
        try container.encode(pathScope, forKey: .pathScope)
        try container.encode(provenanceFilter, forKey: .provenanceFilter)
        try container.encode(queryId, forKey: .queryId)
        try container.encode(queryKind, forKey: .queryKind)
        try container.encode(repoId, forKey: .repoId)
        try container.encode(viewFilter, forKey: .viewFilter)
        try container.encode(worktreeId, forKey: .worktreeId)
    }
}
