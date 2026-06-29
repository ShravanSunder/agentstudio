import Foundation

struct GlobalPreferencesPayload: Decodable, Equatable, Sendable {
    let schemaVersion: Int
    let observability: GlobalObservabilityPreferencesPayload

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case observability
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try Self.rejectUnknownKeys(in: decoder, allowedKeys: CodingKeys.allCases.map(\.stringValue))
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        observability = try container.decode(GlobalObservabilityPreferencesPayload.self, forKey: .observability)
    }

    fileprivate static func rejectUnknownKeys(in decoder: Decoder, allowedKeys: [String]) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let allowedKeySet = Set(allowedKeys)
        if container.allKeys.contains(where: { !allowedKeySet.contains($0.stringValue) }) {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown preference key")
            )
        }
    }
}

struct GlobalObservabilityPreferencesPayload: Decodable, Equatable, Sendable {
    let enabled: Bool
    let traceTags: String?
    let traceBackend: String?
    let traceFlush: String?
    let otlpEndpoint: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case enabled
        case traceTags
        case traceBackend
        case traceFlush
        case otlpEndpoint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try GlobalPreferencesPayload.rejectUnknownKeys(in: decoder, allowedKeys: CodingKeys.allCases.map(\.stringValue))
        enabled = try container.decode(Bool.self, forKey: .enabled)
        traceTags = try container.decodeIfPresent(String.self, forKey: .traceTags)
        traceBackend = try container.decodeIfPresent(String.self, forKey: .traceBackend)
        traceFlush = try container.decodeIfPresent(String.self, forKey: .traceFlush)
        otlpEndpoint = try container.decodeIfPresent(String.self, forKey: .otlpEndpoint)
    }

    func preferences() -> GlobalObservabilityPreferences {
        GlobalObservabilityPreferences(
            enabled: enabled,
            traceTags: traceTags,
            traceBackend: traceBackend,
            traceFlush: traceFlush,
            otlpEndpoint: otlpEndpoint
        )
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
