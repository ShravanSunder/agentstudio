enum BridgeTelemetryStreamId: String, Codable, Equatable, Sendable {
    case page
    case commWorker = "comm-worker"
}

struct BridgeTelemetryBatch: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let scenario: String
    let streamId: BridgeTelemetryStreamId
    let sequence: Int?
    let samples: [BridgeTelemetrySample]

    init(
        schemaVersion: Int,
        scenario: String,
        streamId: BridgeTelemetryStreamId = .page,
        sequence: Int? = nil,
        samples: [BridgeTelemetrySample]
    ) {
        self.schemaVersion = schemaVersion
        self.scenario = scenario
        self.streamId = streamId
        self.sequence = sequence
        self.samples = samples
    }
}
