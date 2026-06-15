struct BridgeTelemetryAggregator: Sendable {
    func dropSample(
        reason: BridgeTelemetryDropReason,
        count: Int
    ) -> BridgeTelemetrySample {
        BridgeTelemetrySample(
            scope: .web,
            name: "performance.bridge.web.telemetry_drop",
            durationMilliseconds: nil,
            traceContext: nil,
            stringAttributes: [
                "agentstudio.bridge.telemetry.drop_reason": reason.rawValue
            ],
            numericAttributes: [
                "agentstudio.bridge.telemetry.dropped_count": Double(count)
            ],
            booleanAttributes: [:]
        )
    }
}
