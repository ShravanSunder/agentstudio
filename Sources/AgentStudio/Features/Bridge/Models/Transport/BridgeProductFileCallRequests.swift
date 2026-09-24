import Foundation

struct BridgeProductFileSourceCurrentRequest: Codable, Equatable, Sendable {
    private struct EmptyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue _: String) { nil }
        init?(intValue _: Int) { nil }
    }

    init() {}

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: [],
            contract: "file.source.current request"
        )
        _ = try decoder.container(keyedBy: EmptyCodingKey.self)
    }

    func encode(to encoder: Encoder) throws {
        _ = encoder.container(keyedBy: EmptyCodingKey.self)
    }
}

struct BridgeProductFileRefreshRetryRequest: Codable, Equatable, Sendable {
    private struct EmptyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue _: String) { nil }
        init?(intValue _: Int) { nil }
    }

    init() {}

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: [],
            contract: "file.refresh.retry request"
        )
        _ = try decoder.container(keyedBy: EmptyCodingKey.self)
    }

    func encode(to encoder: Encoder) throws {
        _ = encoder.container(keyedBy: EmptyCodingKey.self)
    }
}

/// How the File viewer ended a selection: `displayed` once its content is on
/// screen, `unavailable` when it cannot render, `refused` when a native
/// navigation could not leave a document whose editor failed to flush, and
/// `notListed` when the unfiltered tree has no such file row.
enum BridgeProductFileSelectionReceiptOutcome: String, Codable, Equatable, Sendable {
    case displayed
    case notListed
    case refused
    case unavailable
}

struct BridgeProductFileSelectionReceiptSource: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceId
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
            contract: "file selection receipt source"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
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
}

/// The File viewer's receipt for the selection it actually displayed, or for a
/// native file navigation it could not display. Native maps the display path
/// back through the collection it issued and ignores receipts from an older
/// collection source.
struct BridgeProductFileSelectionReceiptRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case displayPath
        case nativeNavigationCommandId
        case outcome
        case source
    }

    let displayPath: String
    let nativeNavigationCommandId: String?
    let outcome: BridgeProductFileSelectionReceiptOutcome
    let source: BridgeProductFileSelectionReceiptSource

    init(
        displayPath: String,
        nativeNavigationCommandId: String?,
        outcome: BridgeProductFileSelectionReceiptOutcome,
        source: BridgeProductFileSelectionReceiptSource
    ) {
        self.displayPath = displayPath
        self.nativeNavigationCommandId = nativeNavigationCommandId
        self.outcome = outcome
        self.source = source
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "file.selection.receipt request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayPath = try container.decode(String.self, forKey: .displayPath)
        nativeNavigationCommandId = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .nativeNavigationCommandId,
            from: container,
            codingPath: decoder.codingPath
        )
        outcome = try container.decode(BridgeProductFileSelectionReceiptOutcome.self, forKey: .outcome)
        source = try container.decode(BridgeProductFileSelectionReceiptSource.self, forKey: .source)
        try BridgeProductContractDecoding.validateDisplayPath(displayPath, codingPath: decoder.codingPath)
        if let nativeNavigationCommandId {
            try BridgeProductContractDecoding.validateIdentifier(
                nativeNavigationCommandId,
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayPath, forKey: .displayPath)
        if let nativeNavigationCommandId {
            try container.encode(nativeNavigationCommandId, forKey: .nativeNavigationCommandId)
        } else {
            try container.encodeNil(forKey: .nativeNavigationCommandId)
        }
        try container.encode(outcome, forKey: .outcome)
        try container.encode(source, forKey: .source)
    }
}
