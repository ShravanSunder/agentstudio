struct BridgeTelemetrySample: Codable, Equatable, Sendable {
    let scope: BridgeTelemetryScope
    let name: String
    let durationMilliseconds: Double?
    let traceContext: BridgeTraceContext?
    let stringAttributes: [String: String]
    let numericAttributes: [String: Double]
    let booleanAttributes: [String: Bool]
}
