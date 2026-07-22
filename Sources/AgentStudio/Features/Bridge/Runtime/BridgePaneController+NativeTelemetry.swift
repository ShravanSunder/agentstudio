import Foundation

@MainActor
extension BridgePaneController {
    func makeRootTraceContext() -> BridgeTraceContext? {
        guard telemetryScopeGate.isEnabled else {
            return nil
        }
        return traceContextFactory.makeRootContext()
    }

    func makeChildTraceContext(parent: BridgeTraceContext?) -> BridgeTraceContext? {
        guard telemetryScopeGate.isEnabled else {
            return nil
        }
        return traceContextFactory.makeChildContext(parent: parent)
    }

    func recordSwiftTelemetry(
        name: String,
        phase: String,
        priorityHint: BridgeTelemetryPriority,
        traceContext: BridgeTraceContext?,
        stringAttributes additionalStringAttributes: [String: String] = [:],
        durationMilliseconds: Double?
    ) async {
        guard let telemetryRecorder else {
            return
        }
        var stringAttributes = [
            "agentstudio.bridge.phase": phase,
            "agentstudio.bridge.plane": nativeTelemetryPlane(for: name).rawValue,
            "agentstudio.bridge.priority": nativeTelemetryPriority(
                for: name,
                fallback: priorityHint
            ).rawValue,
            "agentstudio.bridge.slice": nativeTelemetrySlice(for: name).rawValue,
            "agentstudio.bridge.transport": "swift",
        ]
        stringAttributes.merge(additionalStringAttributes) { _, newValue in newValue }
        await telemetryRecorder.record(
            sample: BridgeTelemetrySample(
                scope: .swift,
                name: name,
                durationMilliseconds: durationMilliseconds,
                traceContext: traceContext,
                stringAttributes: stringAttributes,
                numericAttributes: [:],
                booleanAttributes: [:]
            ),
            receivedAtUnixNano: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
    }

    private func nativeTelemetryPlane(for name: String) -> BridgeTelemetryPlane {
        switch name {
        case "performance.bridge.swift.telemetry_ingest":
            .observability
        default:
            .data
        }
    }

    private func nativeTelemetryPriority(
        for name: String,
        fallback: BridgeTelemetryPriority
    ) -> BridgeTelemetryPriority {
        switch name {
        case "performance.bridge.swift.content_load":
            .hot
        case "performance.bridge.swift.delta_build":
            .warm
        case "performance.bridge.swift.package_build",
            "performance.bridge.swift.content_register":
            .cold
        case "performance.bridge.swift.telemetry_ingest":
            .bestEffort
        default:
            fallback
        }
    }

    private func nativeTelemetrySlice(for name: String) -> BridgeTelemetrySlice {
        switch name {
        case "performance.bridge.swift.package_build",
            "performance.bridge.swift.content_register":
            .reviewMetadata
        case "performance.bridge.swift.delta_build":
            .reviewDelta
        case "performance.bridge.swift.content_load":
            .contentFetch
        case "performance.bridge.swift.telemetry_ingest":
            .telemetryIngest
        default:
            .unknown
        }
    }
}
