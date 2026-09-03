import AgentStudioInfrastructure
import Foundation

struct BridgeReviewRefreshLifecycleTraceEvent: Equatable, Sendable {
    enum Phase: String, Sendable {
        case classified = "review_refresh_classified"
        case sourceCleanupTerminal = "review_refresh_source_cleanup_terminal"
    }

    enum ResultReason: String, Sendable {
        case close
        case commits
        case files
        case lines
        case noReason = "none"
        case unknown
    }

    let phase: Phase
    let resultReason: ResultReason
    let presentationClass: String?
    let reviewGeneration: Int?
    let importedCommitCount: Int?
    let affectedFileCount: Int?
    let changedLineCount: Int?
    let affectedStableFileCount: Int?
    let retainedPublicationCount: Int?
    let sourceLeaseCount: Int?
    let durationMilliseconds: Double?
    let traceContext: BridgeTraceContext?
}

struct BridgeReviewRefreshLifecycleTraceRecorder: Sendable {
    private let recorder: any BridgePerformanceTraceRecording

    init(recorder: any BridgePerformanceTraceRecording) {
        self.recorder = recorder
    }

    func record(_ event: BridgeReviewRefreshLifecycleTraceEvent) async {
        var stringAttributes = [
            "agentstudio.bridge.phase": event.phase.rawValue,
            "agentstudio.bridge.plane": BridgeTelemetryPlane.control.rawValue,
            "agentstudio.bridge.priority": BridgeTelemetryPriority.hot.rawValue,
            "agentstudio.bridge.result": "success",
            "agentstudio.bridge.result_reason": event.resultReason.rawValue,
            "agentstudio.bridge.slice": BridgeTelemetrySlice.reviewMetadata.rawValue,
            "agentstudio.bridge.transport": "swift",
        ]
        if let presentationClass = event.presentationClass {
            stringAttributes["agentstudio.bridge.review.refresh.presentation_class"] =
                presentationClass
        }
        var numericAttributes: [String: Double] = [:]
        Self.add(event.reviewGeneration, as: "agentstudio.bridge.review.generation", to: &numericAttributes)
        Self.add(
            event.importedCommitCount,
            as: "agentstudio.bridge.review.refresh.imported_commit.count",
            to: &numericAttributes
        )
        Self.add(
            event.affectedFileCount,
            as: "agentstudio.bridge.review.refresh.affected_file.count",
            to: &numericAttributes
        )
        Self.add(
            event.changedLineCount,
            as: "agentstudio.bridge.review.refresh.changed_line.count",
            to: &numericAttributes
        )
        Self.add(
            event.affectedStableFileCount,
            as: "agentstudio.bridge.review.refresh.affected_stable_file.count",
            to: &numericAttributes
        )
        Self.add(
            event.retainedPublicationCount,
            as: "agentstudio.bridge.review.refresh.retained_publication.count",
            to: &numericAttributes
        )
        Self.add(
            event.sourceLeaseCount,
            as: "agentstudio.bridge.review.refresh.source_lease.count",
            to: &numericAttributes
        )
        await recorder.record(
            sample: BridgeTelemetrySample(
                scope: .swift,
                name: "performance.bridge.swift.review_refresh_lifecycle",
                durationMilliseconds: event.durationMilliseconds,
                traceContext: event.traceContext,
                stringAttributes: stringAttributes,
                numericAttributes: numericAttributes,
                booleanAttributes: [:]
            ),
            receivedAtUnixNano: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
    }

    private static func add(
        _ value: Int?,
        as key: String,
        to attributes: inout [String: Double]
    ) {
        guard let value else { return }
        attributes[key] = Double(value)
    }
}
