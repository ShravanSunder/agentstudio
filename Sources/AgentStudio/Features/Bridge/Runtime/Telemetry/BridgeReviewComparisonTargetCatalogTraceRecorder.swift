import AgentStudioInfrastructure
import Foundation

struct BridgeReviewComparisonTargetCatalogTraceEvent: Equatable, Sendable {
    enum Stage: String, Sendable {
        case authorization
        case reservationClaim = "reservation_claim"
        case scheduledCapture = "scheduled_capture"
        case encode
        case terminal
    }

    enum Outcome: String, Sendable {
        case success
        case unavailable
        case claimed
        case inactive
        case cancelled
        case failed
        case complete
        case unsupportedContent = "unsupported_content"
        case productionFailed = "production_failed"
    }

    let stage: Stage
    let outcome: Outcome
    let queryRequestSequence: Int?
    let durationMilliseconds: Double?
    let reservationAgeMilliseconds: Double?
    let inputRowCount: Int?
    let outputRowCount: Int?
    let observedByteCount: Int?
    let isTruncated: Bool?

    static func milliseconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

protocol BridgeReviewComparisonTargetCatalogTraceRecording: Sendable {
    func record(_ event: BridgeReviewComparisonTargetCatalogTraceEvent) async
}

extension BridgeReviewComparisonTargetCatalogTraceRecording {
    nonisolated func submit(_ event: BridgeReviewComparisonTargetCatalogTraceEvent) {
        Task {
            await record(event)
        }
    }
}

struct BridgeReviewComparisonTargetCatalogTraceRecorder:
    BridgeReviewComparisonTargetCatalogTraceRecording
{
    private let recorder: any BridgePerformanceTraceRecording
    private let timeUnixNano: @Sendable () -> UInt64

    init(
        recorder: any BridgePerformanceTraceRecording,
        timeUnixNano: @escaping @Sendable () -> UInt64 = {
            UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        }
    ) {
        self.recorder = recorder
        self.timeUnixNano = timeUnixNano
    }

    func record(_ event: BridgeReviewComparisonTargetCatalogTraceEvent) async {
        var numericAttributes: [String: Double] = [:]
        if let queryRequestSequence = event.queryRequestSequence {
            numericAttributes["agentstudio.bridge.review.comparison_targets.query_request.sequence"] =
                Double(queryRequestSequence)
        }
        if let reservationAgeMilliseconds = event.reservationAgeMilliseconds {
            numericAttributes["agentstudio.bridge.review.comparison_targets.reservation_age_ms"] =
                reservationAgeMilliseconds
        }
        if let inputRowCount = event.inputRowCount {
            numericAttributes["agentstudio.bridge.review.comparison_targets.input_row.count"] =
                Double(inputRowCount)
        }
        if let outputRowCount = event.outputRowCount {
            numericAttributes["agentstudio.bridge.review.comparison_targets.output_row.count"] =
                Double(outputRowCount)
        }
        if let observedByteCount = event.observedByteCount {
            numericAttributes["agentstudio.bridge.content.byte_count"] = Double(observedByteCount)
        }

        var booleanAttributes: [String: Bool] = [:]
        if let isTruncated = event.isTruncated {
            booleanAttributes["agentstudio.bridge.review.comparison_targets.is_truncated"] =
                isTruncated
        }

        await recorder.record(
            sample: BridgeTelemetrySample(
                scope: .swift,
                name: "performance.bridge.swift.comparison_target_catalog",
                durationMilliseconds: event.durationMilliseconds,
                traceContext: nil,
                stringAttributes: [
                    "agentstudio.bridge.phase": event.stage.rawValue,
                    "agentstudio.bridge.plane": plane(for: event.stage).rawValue,
                    "agentstudio.bridge.priority": priority(for: event.stage).rawValue,
                    "agentstudio.bridge.result": event.outcome.rawValue,
                    "agentstudio.bridge.result_reason": "none",
                    "agentstudio.bridge.slice": slice(for: event.stage).rawValue,
                    "agentstudio.bridge.transport": "swift",
                    "agentstudio.bridge.viewer": "review",
                ],
                numericAttributes: numericAttributes,
                booleanAttributes: booleanAttributes
            ),
            receivedAtUnixNano: timeUnixNano()
        )
    }

    private func plane(
        for stage: BridgeReviewComparisonTargetCatalogTraceEvent.Stage
    ) -> BridgeTelemetryPlane {
        switch stage {
        case .authorization, .reservationClaim:
            .control
        case .scheduledCapture, .encode, .terminal:
            .data
        }
    }

    private func priority(
        for stage: BridgeReviewComparisonTargetCatalogTraceEvent.Stage
    ) -> BridgeTelemetryPriority {
        switch stage {
        case .authorization, .reservationClaim:
            .warm
        case .scheduledCapture, .encode, .terminal:
            .cold
        }
    }

    private func slice(
        for stage: BridgeReviewComparisonTargetCatalogTraceEvent.Stage
    ) -> BridgeTelemetrySlice {
        switch stage {
        case .authorization, .reservationClaim:
            .reviewRPC
        case .scheduledCapture, .encode, .terminal:
            .contentFetch
        }
    }
}
