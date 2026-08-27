import Foundation

enum BridgeProductMetadataCatalogCapacity {
    static let maximumEncodedEntryBytes = 8 * 1024 * 1024
    static let maximumEntryCount = 200_000

    static func admits(entryCount: Int, encodedEntryBytes: Int) -> Bool {
        entryCount >= 0
            && entryCount <= maximumEntryCount
            && encodedEntryBytes >= 0
            && encodedEntryBytes <= maximumEncodedEntryBytes
    }
}

enum BridgeProductMetadataCatalogTransfer<Entry>: Codable, Equatable, Sendable
where Entry: Codable & Equatable & Sendable {
    case begin(Begin)
    case window(Window)
    case commit(Commit)

    struct Begin: Codable, Equatable, Sendable {
        fileprivate let transferID: String
        fileprivate let catalogRevision: Int
        let expectedEntryCount: Int
    }

    struct Window: Codable, Equatable, Sendable {
        fileprivate let transferID: String
        fileprivate let catalogRevision: Int
        let windowOrdinal: Int
        let entries: [Entry]
    }

    struct Commit: Codable, Equatable, Sendable {
        fileprivate let transferID: String
        fileprivate let catalogRevision: Int
        let windowCount: Int
        let entryCount: Int
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case catalogRevision
        case entries
        case entryCount
        case expectedEntryCount
        case kind
        case transferID = "transferId"
        case windowCount
        case windowOrdinal
    }

    private enum Kind: String, Codable {
        case begin = "catalog.begin"
        case commit = "catalog.commit"
        case window = "catalog.window"
    }

    static func begin(
        transferID: String,
        catalogRevision: Int,
        expectedEntryCount: Int
    ) -> Self {
        .begin(
            .init(
                transferID: transferID,
                catalogRevision: catalogRevision,
                expectedEntryCount: expectedEntryCount
            )
        )
    }

    static func window(
        transferID: String,
        catalogRevision: Int,
        windowOrdinal: Int,
        entries: [Entry]
    ) -> Self {
        .window(
            .init(
                transferID: transferID,
                catalogRevision: catalogRevision,
                windowOrdinal: windowOrdinal,
                entries: entries
            )
        )
    }

    static func commit(
        transferID: String,
        catalogRevision: Int,
        windowCount: Int,
        entryCount: Int
    ) -> Self {
        .commit(
            .init(
                transferID: transferID,
                catalogRevision: catalogRevision,
                windowCount: windowCount,
                entryCount: entryCount
            )
        )
    }

    var transferID: String {
        switch self {
        case .begin(let phase): phase.transferID
        case .window(let phase): phase.transferID
        case .commit(let phase): phase.transferID
        }
    }

    var catalogRevision: Int {
        switch self {
        case .begin(let phase): phase.catalogRevision
        case .window(let phase): phase.catalogRevision
        case .commit(let phase): phase.catalogRevision
        }
    }

    var expectedEntryCount: Int? {
        guard case .begin(let phase) = self else { return nil }
        return phase.expectedEntryCount
    }

    var windowOrdinal: Int? {
        guard case .window(let phase) = self else { return nil }
        return phase.windowOrdinal
    }

    var entries: [Entry]? {
        guard case .window(let phase) = self else { return nil }
        return phase.entries
    }

    var windowCount: Int? {
        guard case .commit(let phase) = self else { return nil }
        return phase.windowCount
    }

    var entryCount: Int? {
        guard case .commit(let phase) = self else { return nil }
        return phase.entryCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let allowedKeys: Set<String>
        switch kind {
        case .begin:
            allowedKeys = [
                CodingKeys.kind.rawValue,
                CodingKeys.transferID.rawValue,
                CodingKeys.catalogRevision.rawValue,
                CodingKeys.expectedEntryCount.rawValue,
            ]
        case .window:
            allowedKeys = [
                CodingKeys.kind.rawValue,
                CodingKeys.transferID.rawValue,
                CodingKeys.catalogRevision.rawValue,
                CodingKeys.windowOrdinal.rawValue,
                CodingKeys.entries.rawValue,
            ]
        case .commit:
            allowedKeys = [
                CodingKeys.kind.rawValue,
                CodingKeys.transferID.rawValue,
                CodingKeys.catalogRevision.rawValue,
                CodingKeys.windowCount.rawValue,
                CodingKeys.entryCount.rawValue,
            ]
        }
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: allowedKeys,
            contract: "metadata catalog transfer"
        )

        let transferID = try container.decode(String.self, forKey: .transferID)
        let catalogRevision = try container.decode(Int.self, forKey: .catalogRevision)
        try Self.validateCommon(
            transferID: transferID,
            catalogRevision: catalogRevision,
            codingPath: decoder.codingPath
        )
        switch kind {
        case .begin:
            let expectedEntryCount = try container.decode(Int.self, forKey: .expectedEntryCount)
            try Self.validateEntryCount(
                expectedEntryCount,
                name: "expectedEntryCount",
                codingPath: decoder.codingPath
            )
            self = .begin(
                .init(
                    transferID: transferID,
                    catalogRevision: catalogRevision,
                    expectedEntryCount: expectedEntryCount
                )
            )
        case .window:
            let windowOrdinal = try container.decode(Int.self, forKey: .windowOrdinal)
            let entries = try container.decode([Entry].self, forKey: .entries)
            try Self.validateCount(
                windowOrdinal,
                name: "windowOrdinal",
                codingPath: decoder.codingPath
            )
            guard !entries.isEmpty else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Bridge metadata catalog window must contain at least one entry",
                    codingPath: decoder.codingPath
                )
            }
            try Self.validateEntryCount(
                entries.count,
                name: "entries",
                codingPath: decoder.codingPath
            )
            self = .window(
                .init(
                    transferID: transferID,
                    catalogRevision: catalogRevision,
                    windowOrdinal: windowOrdinal,
                    entries: entries
                )
            )
        case .commit:
            let windowCount = try container.decode(Int.self, forKey: .windowCount)
            let entryCount = try container.decode(Int.self, forKey: .entryCount)
            try Self.validateCount(windowCount, name: "windowCount", codingPath: decoder.codingPath)
            try Self.validateEntryCount(
                entryCount,
                name: "entryCount",
                codingPath: decoder.codingPath
            )
            self = .commit(
                .init(
                    transferID: transferID,
                    catalogRevision: catalogRevision,
                    windowCount: windowCount,
                    entryCount: entryCount
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        try Self.validateCommon(
            transferID: transferID,
            catalogRevision: catalogRevision,
            codingPath: encoder.codingPath
        )
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transferID, forKey: .transferID)
        try container.encode(catalogRevision, forKey: .catalogRevision)
        switch self {
        case .begin(let phase):
            try Self.validateEntryCount(
                phase.expectedEntryCount,
                name: "expectedEntryCount",
                codingPath: encoder.codingPath
            )
            try container.encode(Kind.begin, forKey: .kind)
            try container.encode(phase.expectedEntryCount, forKey: .expectedEntryCount)
        case .window(let phase):
            try Self.validateCount(
                phase.windowOrdinal,
                name: "windowOrdinal",
                codingPath: encoder.codingPath
            )
            guard !phase.entries.isEmpty else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Bridge metadata catalog window must contain at least one entry",
                    codingPath: encoder.codingPath
                )
            }
            try Self.validateEntryCount(
                phase.entries.count,
                name: "entries",
                codingPath: encoder.codingPath
            )
            try container.encode(Kind.window, forKey: .kind)
            try container.encode(phase.windowOrdinal, forKey: .windowOrdinal)
            try container.encode(phase.entries, forKey: .entries)
        case .commit(let phase):
            try Self.validateCount(
                phase.windowCount,
                name: "windowCount",
                codingPath: encoder.codingPath
            )
            try Self.validateEntryCount(
                phase.entryCount,
                name: "entryCount",
                codingPath: encoder.codingPath
            )
            try container.encode(Kind.commit, forKey: .kind)
            try container.encode(phase.windowCount, forKey: .windowCount)
            try container.encode(phase.entryCount, forKey: .entryCount)
        }
    }

    private static func validateCommon(
        transferID: String,
        catalogRevision: Int,
        codingPath: [any CodingKey]
    ) throws {
        try BridgeProductContractDecoding.validateIdentifier(
            transferID,
            codingPath: codingPath
        )
        try validateCount(
            catalogRevision,
            name: "catalogRevision",
            codingPath: codingPath
        )
    }

    private static func validateCount(
        _ value: Int,
        name: String,
        codingPath: [any CodingKey]
    ) throws {
        try BridgeProductContractDecoding.validateNonnegative(
            value,
            name: name,
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            value,
            maximum: BridgeProductWireContract.maximumSafeInteger,
            name: name,
            codingPath: codingPath
        )
    }

    private static func validateEntryCount(
        _ value: Int,
        name: String,
        codingPath: [any CodingKey]
    ) throws {
        try validateCount(value, name: name, codingPath: codingPath)
        try BridgeProductContractDecoding.validateMaximum(
            value,
            maximum: BridgeProductMetadataCatalogCapacity.maximumEntryCount,
            name: name,
            codingPath: codingPath
        )
    }
}
