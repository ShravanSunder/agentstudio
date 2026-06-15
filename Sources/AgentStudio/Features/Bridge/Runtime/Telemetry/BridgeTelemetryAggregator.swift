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
                "agentstudio.bridge.phase": "dropped",
                "agentstudio.bridge.plane": BridgeTelemetryPlane.observability.rawValue,
                "agentstudio.bridge.priority": BridgeTelemetryPriority.bestEffort.rawValue,
                "agentstudio.bridge.slice": BridgeTelemetrySlice.telemetryDrop.rawValue,
                "agentstudio.bridge.telemetry.drop_reason": reason.rawValue,
                "agentstudio.bridge.transport": "rpc",
            ],
            numericAttributes: [
                "agentstudio.bridge.telemetry.dropped_count": Double(count)
            ],
            booleanAttributes: [:]
        )
    }
}
