import Foundation

enum BridgeProductReviewMetadataLimits {
    static let maximumWindowEntryCount = 4096
    static let maximumPathScopeCount = 10_000
    static let maximumProvenanceIdentityCount = 1024
    static let maximumProvenanceSourceKindCount = 64
}

enum BridgeProductReviewPublicationIdContract {
    static func decode(
        _ value: String,
        codingPath: [any CodingKey]
    ) throws -> UUID {
        try BridgeProductContractDecoding.validateUUID(value, codingPath: codingPath)
        let bytes = Array(value.utf8)
        guard value == value.lowercased(),
            bytes.count == 36,
            bytes[14] == 0x37,
            let publicationId = UUID(uuidString: value)
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "Review publicationId must be a lowercase canonical UUIDv7",
                codingPath: codingPath
            )
        }
        return publicationId
    }

    static func encode(_ publicationId: UUID) -> String {
        let value = publicationId.uuidString.lowercased()
        precondition(Array(value.utf8)[14] == 0x37, "Review publicationId must be UUIDv7")
        return value
    }
}

struct BridgeProductReviewMetadataIdentity: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case generation
        case packageId
        case publicationId
        case revision
        case sourceIdentity
    }

    static let codingKeyNames = Set(CodingKeys.allCases.map(\.rawValue))

    let generation: Int
    let packageId: String
    let publicationId: UUID
    let revision: Int
    let sourceIdentity: String

    init(
        generation: Int,
        packageId: String,
        publicationId: UUID,
        revision: Int,
        sourceIdentity: String
    ) throws {
        self.generation = generation
        self.packageId = packageId
        self.publicationId = publicationId
        self.revision = revision
        self.sourceIdentity = sourceIdentity
        _ = try BridgeProductReviewPublicationIdContract.decode(
            publicationId.uuidString.lowercased(),
            codingPath: []
        )
        try BridgeProductContractDecoding.validateNonnegative(generation, name: "generation", codingPath: [])
        try BridgeProductContractDecoding.validateIdentifier(packageId, codingPath: [])
        try BridgeProductContractDecoding.validateNonnegative(revision, name: "revision", codingPath: [])
        try BridgeProductContractDecoding.validateIdentifier(sourceIdentity, codingPath: [])
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.generation = try container.decode(Int.self, forKey: .generation)
        self.packageId = try container.decode(String.self, forKey: .packageId)
        let publicationIdValue = try container.decode(String.self, forKey: .publicationId)
        self.publicationId = try BridgeProductReviewPublicationIdContract.decode(
            publicationIdValue,
            codingPath: decoder.codingPath
        )
        self.revision = try container.decode(Int.self, forKey: .revision)
        self.sourceIdentity = try container.decode(String.self, forKey: .sourceIdentity)
        try BridgeProductContractDecoding.validateNonnegative(
            generation,
            name: "generation",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(packageId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            revision,
            name: "revision",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(sourceIdentity, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(generation, forKey: .generation)
        try container.encode(packageId, forKey: .packageId)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(publicationId),
            forKey: .publicationId
        )
        try container.encode(revision, forKey: .revision)
        try container.encode(sourceIdentity, forKey: .sourceIdentity)
    }
}

struct BridgeProductReviewItemWindow: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case finalWindow
        case itemCount
        case startIndex
        case totalItemCount
    }

    let finalWindow: Bool
    let itemCount: Int
    let startIndex: Int
    let totalItemCount: Int

    init(finalWindow: Bool, itemCount: Int, startIndex: Int, totalItemCount: Int) throws {
        self.finalWindow = finalWindow
        self.itemCount = itemCount
        self.startIndex = startIndex
        self.totalItemCount = totalItemCount
        try validateOrderedWindow(
            startIndex: startIndex,
            count: itemCount,
            totalCount: totalItemCount,
            finalWindow: finalWindow,
            countName: "itemCount",
            codingPath: []
        )
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review item window"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.finalWindow = try container.decode(Bool.self, forKey: .finalWindow)
        self.itemCount = try container.decode(Int.self, forKey: .itemCount)
        self.startIndex = try container.decode(Int.self, forKey: .startIndex)
        self.totalItemCount = try container.decode(Int.self, forKey: .totalItemCount)
        try validateOrderedWindow(
            startIndex: startIndex,
            count: itemCount,
            totalCount: totalItemCount,
            finalWindow: finalWindow,
            countName: "itemCount",
            codingPath: decoder.codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(finalWindow, forKey: .finalWindow)
        try container.encode(itemCount, forKey: .itemCount)
        try container.encode(startIndex, forKey: .startIndex)
        try container.encode(totalItemCount, forKey: .totalItemCount)
    }
}

struct BridgeProductReviewTreeWindow: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case finalWindow
        case rowCount
        case startIndex
        case totalRowCount
    }

    let finalWindow: Bool
    let rowCount: Int
    let startIndex: Int
    let totalRowCount: Int

    init(finalWindow: Bool, rowCount: Int, startIndex: Int, totalRowCount: Int) throws {
        self.finalWindow = finalWindow
        self.rowCount = rowCount
        self.startIndex = startIndex
        self.totalRowCount = totalRowCount
        try validateOrderedWindow(
            startIndex: startIndex,
            count: rowCount,
            totalCount: totalRowCount,
            finalWindow: finalWindow,
            countName: "rowCount",
            codingPath: []
        )
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review tree window"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.finalWindow = try container.decode(Bool.self, forKey: .finalWindow)
        self.rowCount = try container.decode(Int.self, forKey: .rowCount)
        self.startIndex = try container.decode(Int.self, forKey: .startIndex)
        self.totalRowCount = try container.decode(Int.self, forKey: .totalRowCount)
        try validateOrderedWindow(
            startIndex: startIndex,
            count: rowCount,
            totalCount: totalRowCount,
            finalWindow: finalWindow,
            countName: "rowCount",
            codingPath: decoder.codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(finalWindow, forKey: .finalWindow)
        try container.encode(rowCount, forKey: .rowCount)
        try container.encode(startIndex, forKey: .startIndex)
        try container.encode(totalRowCount, forKey: .totalRowCount)
    }
}

private func validateOrderedWindow(
    startIndex: Int,
    count: Int,
    totalCount: Int,
    finalWindow: Bool,
    countName: String,
    codingPath: [any CodingKey]
) throws {
    try BridgeProductContractDecoding.validateNonnegative(
        startIndex,
        name: "startIndex",
        codingPath: codingPath
    )
    try BridgeProductContractDecoding.validateNonnegative(count, name: countName, codingPath: codingPath)
    try BridgeProductContractDecoding.validateMaximum(
        count,
        maximum: BridgeProductReviewMetadataLimits.maximumWindowEntryCount,
        name: countName,
        codingPath: codingPath
    )
    try BridgeProductContractDecoding.validateNonnegative(
        totalCount,
        name: "totalCount",
        codingPath: codingPath
    )
    let (endIndex, overflowed) = startIndex.addingReportingOverflow(count)
    guard !overflowed, endIndex <= totalCount else {
        throw BridgeProductContractDecoding.invalidValue(
            "Review metadata window exceeds its ordered total",
            codingPath: codingPath
        )
    }
    guard finalWindow == (endIndex == totalCount) else {
        throw BridgeProductContractDecoding.invalidValue(
            "Review metadata final-window state does not match its ordered extent",
            codingPath: codingPath
        )
    }
}

struct BridgeProductReviewPackageSummaryValue: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case additions
        case deletions
        case filesChanged
        case hiddenFileCount
        case visibleFileCount
    }

    let additions: Int
    let deletions: Int
    let filesChanged: Int
    let hiddenFileCount: Int
    let visibleFileCount: Int

    init(additions: Int, deletions: Int, filesChanged: Int, hiddenFileCount: Int, visibleFileCount: Int) throws {
        self.additions = additions
        self.deletions = deletions
        self.filesChanged = filesChanged
        self.hiddenFileCount = hiddenFileCount
        self.visibleFileCount = visibleFileCount
        for (value, name) in [
            (additions, "additions"),
            (deletions, "deletions"),
            (filesChanged, "filesChanged"),
            (hiddenFileCount, "hiddenFileCount"),
            (visibleFileCount, "visibleFileCount"),
        ] {
            try BridgeProductContractDecoding.validateNonnegative(value, name: name, codingPath: [])
        }
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review package summary"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.additions = try container.decode(Int.self, forKey: .additions)
        self.deletions = try container.decode(Int.self, forKey: .deletions)
        self.filesChanged = try container.decode(Int.self, forKey: .filesChanged)
        self.hiddenFileCount = try container.decode(Int.self, forKey: .hiddenFileCount)
        self.visibleFileCount = try container.decode(Int.self, forKey: .visibleFileCount)
        for (value, name) in [
            (additions, "additions"),
            (deletions, "deletions"),
            (filesChanged, "filesChanged"),
            (hiddenFileCount, "hiddenFileCount"),
            (visibleFileCount, "visibleFileCount"),
        ] {
            try BridgeProductContractDecoding.validateNonnegative(value, name: name, codingPath: decoder.codingPath)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(additions, forKey: .additions)
        try container.encode(deletions, forKey: .deletions)
        try container.encode(filesChanged, forKey: .filesChanged)
        try container.encode(hiddenFileCount, forKey: .hiddenFileCount)
        try container.encode(visibleFileCount, forKey: .visibleFileCount)
    }
}

struct BridgeProductReviewSourceEndpointValue: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contentSetHash
        case createdAtUnixMilliseconds
        case endpointId
        case kind
        case label
        case providerIdentity
        case repoId
        case worktreeId
    }

    let contentSetHash: String?
    let createdAtUnixMilliseconds: Int
    let endpointId: String
    let kind: BridgeSourceEndpoint.Kind
    let label: String
    let providerIdentity: String
    let repoId: String
    let worktreeId: String

    init(
        contentSetHash: String?,
        createdAtUnixMilliseconds: Int,
        endpointId: String,
        kind: BridgeSourceEndpoint.Kind,
        label: String,
        providerIdentity: String,
        repoId: String,
        worktreeId: String
    ) throws {
        self.contentSetHash = contentSetHash
        self.createdAtUnixMilliseconds = createdAtUnixMilliseconds
        self.endpointId = endpointId
        self.kind = kind
        self.label = label
        self.providerIdentity = providerIdentity
        self.repoId = repoId
        self.worktreeId = worktreeId
        if let contentSetHash {
            try BridgeProductContractDecoding.validateOpaqueReference(contentSetHash, codingPath: [])
        }
        try BridgeProductContractDecoding.validateNonnegative(
            createdAtUnixMilliseconds,
            name: "createdAtUnixMilliseconds",
            codingPath: []
        )
        try BridgeProductContractDecoding.validateIdentifier(endpointId, codingPath: [])
        try BridgeProductContractDecoding.validateSafeMessage(label, codingPath: [])
        try BridgeProductContractDecoding.validateOpaqueReference(providerIdentity, codingPath: [])
        try BridgeProductContractDecoding.validateIdentifier(repoId, codingPath: [])
        try BridgeProductContractDecoding.validateIdentifier(worktreeId, codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review source endpoint"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.contentSetHash = try container.decodeIfPresent(String.self, forKey: .contentSetHash)
        self.createdAtUnixMilliseconds = try container.decode(Int.self, forKey: .createdAtUnixMilliseconds)
        self.endpointId = try container.decode(String.self, forKey: .endpointId)
        self.kind = try container.decode(BridgeSourceEndpoint.Kind.self, forKey: .kind)
        self.label = try container.decode(String.self, forKey: .label)
        self.providerIdentity = try container.decode(String.self, forKey: .providerIdentity)
        self.repoId = try container.decode(String.self, forKey: .repoId)
        self.worktreeId = try container.decode(String.self, forKey: .worktreeId)
        if let contentSetHash {
            try BridgeProductContractDecoding.validateOpaqueReference(contentSetHash, codingPath: decoder.codingPath)
        }
        try BridgeProductContractDecoding.validateNonnegative(
            createdAtUnixMilliseconds,
            name: "createdAtUnixMilliseconds",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(endpointId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateSafeMessage(label, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateOpaqueReference(providerIdentity, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(repoId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(worktreeId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(contentSetHash, forKey: .contentSetHash)
        try container.encode(createdAtUnixMilliseconds, forKey: .createdAtUnixMilliseconds)
        try container.encode(endpointId, forKey: .endpointId)
        try container.encode(kind, forKey: .kind)
        try container.encode(label, forKey: .label)
        try container.encode(providerIdentity, forKey: .providerIdentity)
        try container.encode(repoId, forKey: .repoId)
        try container.encode(worktreeId, forKey: .worktreeId)
    }
}

struct BridgeProductReviewGroupingValue: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case label
    }

    let kind: BridgeChangeGrouping.Kind
    let label: String?

    init(kind: BridgeChangeGrouping.Kind, label: String?) throws {
        self.kind = kind
        self.label = label
        if let label {
            try BridgeProductContractDecoding.validateSafeMessage(label, codingPath: [])
        }
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review grouping"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decode(BridgeChangeGrouping.Kind.self, forKey: .kind)
        self.label = try container.decodeIfPresent(String.self, forKey: .label)
        if let label {
            try BridgeProductContractDecoding.validateSafeMessage(label, codingPath: decoder.codingPath)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(label, forKey: .label)
    }
}
