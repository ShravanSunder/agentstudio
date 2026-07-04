struct BridgeTelemetryBatch: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let scenario: String
    let sequence: Int?
    let samples: [BridgeTelemetrySample]

    init(
        schemaVersion: Int,
        scenario: String,
        sequence: Int? = nil,
        samples: [BridgeTelemetrySample]
    ) {
        self.schemaVersion = schemaVersion
        self.scenario = scenario
        self.sequence = sequence
        self.samples = samples
    }
}
