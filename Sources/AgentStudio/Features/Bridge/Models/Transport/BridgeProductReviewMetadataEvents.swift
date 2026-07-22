import Foundation

enum BridgeProductReviewMetadataOperation: Codable, Equatable, Sendable {
    case upsertItem(BridgeProductReviewItemMetadataValue)
    case removeItems([String])
    case replaceItemOrder([String])
    case spliceTreeRows(startIndex: Int, deleteCount: Int, rows: [BridgeProductReviewTreeRowValue])
    case upsertExtentFacts([BridgeProductReviewExtentFactValue])
    case invalidateContentSources([String])

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case deleteCount
        case descriptorIds
        case facts
        case item
        case itemIds
        case operationKind
        case rows
        case startIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .operationKind) {
        case "upsertItem":
            try Self.rejectUnknownKeys(from: decoder, allowedKeys: [.item, .operationKind])
            self = .upsertItem(try container.decode(BridgeProductReviewItemMetadataValue.self, forKey: .item))
        case "removeItems":
            try Self.rejectUnknownKeys(from: decoder, allowedKeys: [.itemIds, .operationKind])
            let itemIds = try container.decode([String].self, forKey: .itemIds)
            try Self.validateUniqueIdentifiers(itemIds, name: "removed itemIds", codingPath: decoder.codingPath)
            self = .removeItems(itemIds)
        case "replaceItemOrder":
            try Self.rejectUnknownKeys(from: decoder, allowedKeys: [.itemIds, .operationKind])
            let itemIds = try container.decode([String].self, forKey: .itemIds)
            try Self.validateUniqueIdentifiers(itemIds, name: "replacement itemIds", codingPath: decoder.codingPath)
            self = .replaceItemOrder(itemIds)
        case "spliceTreeRows":
            try Self.rejectUnknownKeys(
                from: decoder,
                allowedKeys: [.deleteCount, .operationKind, .rows, .startIndex]
            )
            let startIndex = try container.decode(Int.self, forKey: .startIndex)
            let deleteCount = try container.decode(Int.self, forKey: .deleteCount)
            let rows = try container.decode([BridgeProductReviewTreeRowValue].self, forKey: .rows)
            try BridgeProductContractDecoding.validateNonnegative(
                startIndex,
                name: "startIndex",
                codingPath: decoder.codingPath
            )
            try BridgeProductContractDecoding.validateNonnegative(
                deleteCount,
                name: "deleteCount",
                codingPath: decoder.codingPath
            )
            try BridgeProductContractDecoding.validateMaximum(
                deleteCount,
                maximum: BridgeProductReviewMetadataLimits.maximumWindowEntryCount,
                name: "deleteCount",
                codingPath: decoder.codingPath
            )
            try Self.validateCount(rows.count, name: "splice rows", codingPath: decoder.codingPath)
            self = .spliceTreeRows(startIndex: startIndex, deleteCount: deleteCount, rows: rows)
        case "upsertExtentFacts":
            try Self.rejectUnknownKeys(from: decoder, allowedKeys: [.facts, .operationKind])
            let facts = try container.decode([BridgeProductReviewExtentFactValue].self, forKey: .facts)
            try Self.validateCount(facts.count, name: "extent facts", codingPath: decoder.codingPath)
            self = .upsertExtentFacts(facts)
        case "invalidateContentSources":
            try Self.rejectUnknownKeys(from: decoder, allowedKeys: [.descriptorIds, .operationKind])
            let descriptorIds = try container.decode([String].self, forKey: .descriptorIds)
            try Self.validateUniqueIdentifiers(
                descriptorIds,
                name: "invalidated descriptorIds",
                codingPath: decoder.codingPath
            )
            self = .invalidateContentSources(descriptorIds)
        default:
            throw BridgeProductContractDecoding.invalidValue(
                "Unknown Review metadata operation",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .upsertItem(let item):
            try container.encode(item, forKey: .item)
            try container.encode("upsertItem", forKey: .operationKind)
        case .removeItems(let itemIds):
            try container.encode(itemIds, forKey: .itemIds)
            try container.encode("removeItems", forKey: .operationKind)
        case .replaceItemOrder(let itemIds):
            try container.encode(itemIds, forKey: .itemIds)
            try container.encode("replaceItemOrder", forKey: .operationKind)
        case .spliceTreeRows(let startIndex, let deleteCount, let rows):
            try container.encode(deleteCount, forKey: .deleteCount)
            try container.encode("spliceTreeRows", forKey: .operationKind)
            try container.encode(rows, forKey: .rows)
            try container.encode(startIndex, forKey: .startIndex)
        case .upsertExtentFacts(let facts):
            try container.encode(facts, forKey: .facts)
            try container.encode("upsertExtentFacts", forKey: .operationKind)
        case .invalidateContentSources(let descriptorIds):
            try container.encode(descriptorIds, forKey: .descriptorIds)
            try container.encode("invalidateContentSources", forKey: .operationKind)
        }
    }

    private static func rejectUnknownKeys(from decoder: Decoder, allowedKeys: Set<CodingKeys>) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(allowedKeys.map(\.rawValue)),
            contract: "Review metadata operation"
        )
    }

    private static func validateCount(_ count: Int, name: String, codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validateCollectionCount(
            count,
            maximum: BridgeProductReviewMetadataLimits.maximumWindowEntryCount,
            name: name,
            codingPath: codingPath
        )
    }

    private static func validateUniqueIdentifiers(
        _ values: [String],
        name: String,
        codingPath: [any CodingKey]
    ) throws {
        try validateCount(values.count, name: name, codingPath: codingPath)
        for value in values {
            try BridgeProductContractDecoding.validateIdentifier(value, codingPath: codingPath)
        }
        guard Set(values).count == values.count else {
            throw BridgeProductContractDecoding.invalidValue(
                "Review metadata \(name) must be unique",
                codingPath: codingPath
            )
        }
    }
}

private struct BridgeProductReviewMetadataPayload: Equatable, Sendable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case contentSources
        case extentFacts
        case itemMetadata
        case summary
        case treeRows
    }

    static let codingKeyNames = Set(CodingKeys.allCases.map(\.rawValue))

    let contentSources: [BridgeProductReviewContentSourceDescriptor]
    let extentFacts: [BridgeProductReviewExtentFactValue]
    let itemMetadata: [BridgeProductReviewItemMetadataValue]
    let summary: BridgeProductReviewPackageSummaryValue
    let treeRows: [BridgeProductReviewTreeRowValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.contentSources = try container.decode(
            [BridgeProductReviewContentSourceDescriptor].self,
            forKey: .contentSources
        )
        self.extentFacts = try container.decode([BridgeProductReviewExtentFactValue].self, forKey: .extentFacts)
        self.itemMetadata = try container.decode([BridgeProductReviewItemMetadataValue].self, forKey: .itemMetadata)
        self.summary = try container.decode(BridgeProductReviewPackageSummaryValue.self, forKey: .summary)
        self.treeRows = try container.decode([BridgeProductReviewTreeRowValue].self, forKey: .treeRows)
        for (count, name) in [
            (contentSources.count, "contentSources"),
            (extentFacts.count, "extentFacts"),
            (itemMetadata.count, "itemMetadata"),
            (treeRows.count, "treeRows"),
        ] {
            try BridgeProductContractDecoding.validateCollectionCount(
                count,
                maximum: BridgeProductReviewMetadataLimits.maximumWindowEntryCount,
                name: name,
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contentSources, forKey: .contentSources)
        try container.encode(extentFacts, forKey: .extentFacts)
        try container.encode(itemMetadata, forKey: .itemMetadata)
        try container.encode(summary, forKey: .summary)
        try container.encode(treeRows, forKey: .treeRows)
    }

    func validate(identity: BridgeProductReviewMetadataIdentity, codingPath: [any CodingKey]) throws {
        for source in contentSources {
            guard source.packageId == identity.packageId,
                source.reviewGeneration == identity.generation,
                source.sourceIdentity == identity.sourceIdentity
            else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Review content source identity does not match its metadata event",
                    codingPath: codingPath
                )
            }
        }
    }
}

struct BridgeProductReviewSourceAcceptedEvent: Codable, Equatable, Sendable {
    let identity: BridgeProductReviewMetadataIdentity

    init(identity: BridgeProductReviewMetadataIdentity) {
        self.identity = identity
    }

    init(from decoder: Decoder) throws {
        try rejectReviewEventUnknownKeys(from: decoder, additionalKeys: [], contract: "Review source accepted event")
        let container = try decoder.container(keyedBy: ReviewEventKindCodingKey.self)
        guard try container.decode(String.self, forKey: .eventKind) == "review.sourceAccepted" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Review source event kind", codingPath: decoder.codingPath)
        }
        self.identity = try BridgeProductReviewMetadataIdentity(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var container = encoder.container(keyedBy: ReviewEventKindCodingKey.self)
        try container.encode("review.sourceAccepted", forKey: .eventKind)
    }
}

struct BridgeProductReviewSnapshotEvent: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case baseEndpoint
        case headEndpoint
        case itemWindow
        case query
        case treeWindow
    }

    let identity: BridgeProductReviewMetadataIdentity
    let baseEndpoint: BridgeProductReviewSourceEndpointValue
    let contentSources: [BridgeProductReviewContentSourceDescriptor]
    let extentFacts: [BridgeProductReviewExtentFactValue]
    let headEndpoint: BridgeProductReviewSourceEndpointValue
    let itemMetadata: [BridgeProductReviewItemMetadataValue]
    let itemWindow: BridgeProductReviewItemWindow
    let query: BridgeProductReviewQueryValue
    let summary: BridgeProductReviewPackageSummaryValue
    let treeRows: [BridgeProductReviewTreeRowValue]
    let treeWindow: BridgeProductReviewTreeWindow

    init(
        identity: BridgeProductReviewMetadataIdentity,
        baseEndpoint: BridgeProductReviewSourceEndpointValue,
        contentSources: [BridgeProductReviewContentSourceDescriptor],
        extentFacts: [BridgeProductReviewExtentFactValue],
        headEndpoint: BridgeProductReviewSourceEndpointValue,
        itemMetadata: [BridgeProductReviewItemMetadataValue],
        itemWindow: BridgeProductReviewItemWindow,
        query: BridgeProductReviewQueryValue,
        summary: BridgeProductReviewPackageSummaryValue,
        treeRows: [BridgeProductReviewTreeRowValue],
        treeWindow: BridgeProductReviewTreeWindow
    ) throws {
        self.identity = identity
        self.baseEndpoint = baseEndpoint
        self.contentSources = contentSources
        self.extentFacts = extentFacts
        self.headEndpoint = headEndpoint
        self.itemMetadata = itemMetadata
        self.itemWindow = itemWindow
        self.query = query
        self.summary = summary
        self.treeRows = treeRows
        self.treeWindow = treeWindow
        try payload.validate(identity: identity, codingPath: [])
        try validateWindowPayload(codingPath: [])
        guard itemWindow.startIndex == 0, treeWindow.startIndex == 0 else {
            throw BridgeProductContractDecoding.invalidValue(
                "Review snapshot windows must start at zero",
                codingPath: []
            )
        }
    }

    init(from decoder: Decoder) throws {
        try rejectReviewEventUnknownKeys(
            from: decoder,
            additionalKeys: BridgeProductReviewMetadataPayload.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)),
            contract: "Review snapshot event"
        )
        let eventContainer = try decoder.container(keyedBy: ReviewEventKindCodingKey.self)
        guard try eventContainer.decode(String.self, forKey: .eventKind) == "review.snapshot" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Review snapshot kind", codingPath: decoder.codingPath)
        }
        self.identity = try BridgeProductReviewMetadataIdentity(from: decoder)
        let payload = try BridgeProductReviewMetadataPayload(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.baseEndpoint = try container.decode(BridgeProductReviewSourceEndpointValue.self, forKey: .baseEndpoint)
        self.contentSources = payload.contentSources
        self.extentFacts = payload.extentFacts
        self.headEndpoint = try container.decode(BridgeProductReviewSourceEndpointValue.self, forKey: .headEndpoint)
        self.itemMetadata = payload.itemMetadata
        self.itemWindow = try container.decode(BridgeProductReviewItemWindow.self, forKey: .itemWindow)
        self.query = try container.decode(BridgeProductReviewQueryValue.self, forKey: .query)
        self.summary = payload.summary
        self.treeRows = payload.treeRows
        self.treeWindow = try container.decode(BridgeProductReviewTreeWindow.self, forKey: .treeWindow)
        try payload.validate(identity: identity, codingPath: decoder.codingPath)
        try validateWindowPayload(codingPath: decoder.codingPath)
        guard itemWindow.startIndex == 0, treeWindow.startIndex == 0 else {
            throw BridgeProductContractDecoding.invalidValue(
                "Review snapshot windows must start at zero",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        try payload.encode(to: encoder)
        var eventContainer = encoder.container(keyedBy: ReviewEventKindCodingKey.self)
        try eventContainer.encode("review.snapshot", forKey: .eventKind)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(baseEndpoint, forKey: .baseEndpoint)
        try container.encode(headEndpoint, forKey: .headEndpoint)
        try container.encode(itemWindow, forKey: .itemWindow)
        try container.encode(query, forKey: .query)
        try container.encode(treeWindow, forKey: .treeWindow)
    }

    private var payload: BridgeProductReviewMetadataPayload {
        .init(
            contentSources: contentSources,
            extentFacts: extentFacts,
            itemMetadata: itemMetadata,
            summary: summary,
            treeRows: treeRows
        )
    }

    private func validateWindowPayload(codingPath: [any CodingKey]) throws {
        guard itemWindow.itemCount == itemMetadata.count, treeWindow.rowCount == treeRows.count else {
            throw BridgeProductContractDecoding.invalidValue(
                "Review metadata window count does not match its payload",
                codingPath: codingPath
            )
        }
    }
}

struct BridgeProductReviewWindowEvent: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case itemWindow
        case treeWindow
    }

    let identity: BridgeProductReviewMetadataIdentity
    let contentSources: [BridgeProductReviewContentSourceDescriptor]
    let extentFacts: [BridgeProductReviewExtentFactValue]
    let itemMetadata: [BridgeProductReviewItemMetadataValue]
    let itemWindow: BridgeProductReviewItemWindow
    let summary: BridgeProductReviewPackageSummaryValue
    let treeRows: [BridgeProductReviewTreeRowValue]
    let treeWindow: BridgeProductReviewTreeWindow

    init(
        identity: BridgeProductReviewMetadataIdentity,
        contentSources: [BridgeProductReviewContentSourceDescriptor],
        extentFacts: [BridgeProductReviewExtentFactValue],
        itemMetadata: [BridgeProductReviewItemMetadataValue],
        itemWindow: BridgeProductReviewItemWindow,
        summary: BridgeProductReviewPackageSummaryValue,
        treeRows: [BridgeProductReviewTreeRowValue],
        treeWindow: BridgeProductReviewTreeWindow
    ) throws {
        self.identity = identity
        self.contentSources = contentSources
        self.extentFacts = extentFacts
        self.itemMetadata = itemMetadata
        self.itemWindow = itemWindow
        self.summary = summary
        self.treeRows = treeRows
        self.treeWindow = treeWindow
        try payload.validate(identity: identity, codingPath: [])
        guard itemWindow.itemCount == itemMetadata.count, treeWindow.rowCount == treeRows.count else {
            throw BridgeProductContractDecoding.invalidValue(
                "Review metadata window count does not match its payload",
                codingPath: []
            )
        }
    }

    init(from decoder: Decoder) throws {
        try rejectReviewEventUnknownKeys(
            from: decoder,
            additionalKeys: BridgeProductReviewMetadataPayload.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)),
            contract: "Review window event"
        )
        let eventContainer = try decoder.container(keyedBy: ReviewEventKindCodingKey.self)
        guard try eventContainer.decode(String.self, forKey: .eventKind) == "review.window" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Review window kind", codingPath: decoder.codingPath)
        }
        self.identity = try BridgeProductReviewMetadataIdentity(from: decoder)
        let payload = try BridgeProductReviewMetadataPayload(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.contentSources = payload.contentSources
        self.extentFacts = payload.extentFacts
        self.itemMetadata = payload.itemMetadata
        self.itemWindow = try container.decode(BridgeProductReviewItemWindow.self, forKey: .itemWindow)
        self.summary = payload.summary
        self.treeRows = payload.treeRows
        self.treeWindow = try container.decode(BridgeProductReviewTreeWindow.self, forKey: .treeWindow)
        try payload.validate(identity: identity, codingPath: decoder.codingPath)
        guard itemWindow.itemCount == itemMetadata.count, treeWindow.rowCount == treeRows.count else {
            throw BridgeProductContractDecoding.invalidValue(
                "Review metadata window count does not match its payload",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        try payload.encode(to: encoder)
        var eventContainer = encoder.container(keyedBy: ReviewEventKindCodingKey.self)
        try eventContainer.encode("review.window", forKey: .eventKind)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemWindow, forKey: .itemWindow)
        try container.encode(treeWindow, forKey: .treeWindow)
    }

    private var payload: BridgeProductReviewMetadataPayload {
        .init(
            contentSources: contentSources,
            extentFacts: extentFacts,
            itemMetadata: itemMetadata,
            summary: summary,
            treeRows: treeRows
        )
    }
}

extension BridgeProductReviewMetadataPayload {
    fileprivate init(
        contentSources: [BridgeProductReviewContentSourceDescriptor],
        extentFacts: [BridgeProductReviewExtentFactValue],
        itemMetadata: [BridgeProductReviewItemMetadataValue],
        summary: BridgeProductReviewPackageSummaryValue,
        treeRows: [BridgeProductReviewTreeRowValue]
    ) {
        self.contentSources = contentSources
        self.extentFacts = extentFacts
        self.itemMetadata = itemMetadata
        self.summary = summary
        self.treeRows = treeRows
    }
}

private enum ReviewEventKindCodingKey: String, CodingKey {
    case eventKind
}

private func rejectReviewEventUnknownKeys(
    from decoder: Decoder,
    additionalKeys: Set<String>,
    contract: String
) throws {
    try BridgeProductContractDecoding.rejectUnknownKeys(
        from: decoder,
        allowedKeys: BridgeProductReviewMetadataIdentity.codingKeyNames
            .union([ReviewEventKindCodingKey.eventKind.rawValue])
            .union(additionalKeys),
        contract: contract
    )
}
