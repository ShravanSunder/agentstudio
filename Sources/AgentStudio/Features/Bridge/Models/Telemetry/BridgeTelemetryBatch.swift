struct BridgeTelemetryBatch: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let scenario: String
    let samples: [BridgeTelemetrySample]
}
