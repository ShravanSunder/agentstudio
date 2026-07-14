import Foundation

protocol BridgeProductMetadataLifecycleTraceRecording: Sendable {
    func record(_ event: BridgeProductMetadataLifecycleTraceEvent) async
    func record(_ event: BridgeProductReviewMetadataPublicationTraceEvent) async
}

enum BridgeProductReviewMetadataPublicationFailure: String, Equatable, Sendable {
    case cancellation
    case eventConstruction = "event_construction"
    case producerQueueReset = "producer_queue_reset"
    case producerRejection = "producer_rejection"
    case resetEnqueueFailure = "reset_enqueue_failure"
    case unexpected
}

enum BridgeProductReviewMetadataPublicationTraceEvent: Equatable, Sendable {
    case started(retainedSubscriptions: Int, traceContext: BridgeTraceContext?)
    case completed(
        receipt: BridgeReviewMetadataPublicationReceipt,
        traceContext: BridgeTraceContext?
    )
    case failed(
        failure: BridgeProductReviewMetadataPublicationFailure,
        retainedSubscriptions: Int,
        traceContext: BridgeTraceContext?
    )
}

enum BridgeProductMetadataProducerFailureReason: Equatable, Sendable {
    case cancellation
    case fileSourceUnavailable
    case producerQueueReset
    case producerRejection(BridgeProductProducerEnqueueRejection)
    case reviewEventConstruction
    case reviewSourceUnavailable
    case reviewSubscriptionMissing
    case sessionEnqueueFailure
    case taskCancellation
    case unexpected

    var telemetryValue: String {
        switch self {
        case .cancellation:
            "cancellation"
        case .fileSourceUnavailable:
            "file_source_unavailable"
        case .producerQueueReset:
            "producer_queue_reset"
        case .producerRejection(let rejection):
            "producer_rejection_\(rejection.telemetryValue)"
        case .reviewEventConstruction:
            "review_event_construction"
        case .reviewSourceUnavailable:
            "review_source_unavailable"
        case .reviewSubscriptionMissing:
            "review_subscription_missing"
        case .sessionEnqueueFailure:
            "session_enqueue_failure"
        case .taskCancellation:
            "task_cancellation"
        case .unexpected:
            "unexpected"
        }
    }
}

extension BridgeProductProducerEnqueueRejection {
    fileprivate var telemetryValue: String {
        switch self {
        case .closeRequired:
            "close_required"
        case .frameIdentityMismatch:
            "frame_identity_mismatch"
        case .frameKindMismatch:
            "frame_kind_mismatch"
        case .frameLifecycleMismatch:
            "frame_lifecycle_mismatch"
        case .frameTooLarge:
            "frame_too_large"
        case .lifecycleClosed:
            "lifecycle_closed"
        case .openingFrameAlreadyAdmitted:
            "opening_frame_already_admitted"
        case .openingFrameRequired:
            "opening_frame_required"
        case .sequenceExhausted:
            "sequence_exhausted"
        case .terminalAlreadyAdmitted:
            "terminal_already_admitted"
        case .unknownLease:
            "unknown_lease"
        }
    }
}

struct BridgeProductMetadataLifecycleTraceEvent: Sendable {
    enum Stage: String, Sendable {
        case bootstrapStarted = "metadata_bootstrap_started"
        case sourceAcceptedEnqueued = "metadata_source_accepted_enqueued"
        case windowEnqueued = "metadata_window_enqueued"
        case producerCancelled = "metadata_producer_cancelled"
        case producerFailed = "metadata_producer_failed"
        case subscriptionResetEnqueued = "metadata_subscription_reset_enqueued"
        case bootstrapFinished = "metadata_bootstrap_finished"
    }

    enum Result: String, Sendable {
        case failure
        case queued
        case success
    }

    let stage: Stage
    let subscriptionKind: BridgeProductSubscriptionKind
    let result: Result
    let failureReason: BridgeProductMetadataProducerFailureReason?
    let traceContext: BridgeTraceContext?
    let sourceGeneration: Int?
    let rowCount: Int?
    let isFinalWindow: Bool?

    init(
        stage: Stage,
        subscriptionKind: BridgeProductSubscriptionKind,
        result: Result,
        failureReason: BridgeProductMetadataProducerFailureReason? = nil,
        traceContext: BridgeTraceContext?,
        sourceGeneration: Int? = nil,
        rowCount: Int? = nil,
        isFinalWindow: Bool? = nil
    ) {
        self.stage = stage
        self.subscriptionKind = subscriptionKind
        self.result = result
        self.failureReason = failureReason
        self.traceContext = traceContext
        self.sourceGeneration = sourceGeneration
        self.rowCount = rowCount
        self.isFinalWindow = isFinalWindow
    }
}

struct BridgeProductMetadataLifecycleTraceRecorder: BridgeProductMetadataLifecycleTraceRecording {
    private let recorder: any BridgePerformanceTraceRecording

    init(recorder: any BridgePerformanceTraceRecording) {
        self.recorder = recorder
    }

    func record(_ event: BridgeProductMetadataLifecycleTraceEvent) async {
        let protocolName: String
        let viewer: String
        let slice: BridgeTelemetrySlice
        switch event.subscriptionKind {
        case .fileMetadata:
            protocolName = "worktree-file"
            viewer = "file"
            slice = .treePrepareInput
        case .reviewMetadata:
            protocolName = "review"
            viewer = "review"
            slice = .reviewMetadata
        }

        var numericAttributes: [String: Double] = [:]
        if let sourceGeneration = event.sourceGeneration {
            numericAttributes["agentstudio.bridge.source.generation"] = Double(sourceGeneration)
        }
        if let rowCount = event.rowCount {
            numericAttributes["agentstudio.bridge.worktree_file.tree.window.row.count"] = Double(rowCount)
        }
        var booleanAttributes: [String: Bool] = [:]
        if let isFinalWindow = event.isFinalWindow {
            booleanAttributes["agentstudio.bridge.worktree_file.tree.window.is_final"] = isFinalWindow
        }

        var stringAttributes = [
            "agentstudio.bridge.phase": event.stage.rawValue,
            "agentstudio.bridge.plane": BridgeTelemetryPlane.data.rawValue,
            "agentstudio.bridge.priority": BridgeTelemetryPriority.hot.rawValue,
            "agentstudio.bridge.protocol": protocolName,
            "agentstudio.bridge.result": event.result.rawValue,
            "agentstudio.bridge.slice": slice.rawValue,
            "agentstudio.bridge.transport": "swift",
            "agentstudio.bridge.viewer": viewer,
        ]
        if let failureReason = event.failureReason {
            stringAttributes["agentstudio.bridge.result_reason"] = failureReason.telemetryValue
        }

        await recorder.record(
            sample: BridgeTelemetrySample(
                scope: .swift,
                name: "performance.bridge.swift.metadata_bootstrap_lifecycle",
                durationMilliseconds: nil,
                traceContext: event.traceContext,
                stringAttributes: stringAttributes,
                numericAttributes: numericAttributes,
                booleanAttributes: booleanAttributes
            ),
            receivedAtUnixNano: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
    }

    func record(_ event: BridgeProductReviewMetadataPublicationTraceEvent) async {
        let phase: String
        let result: String
        let resultReason: String
        let traceContext: BridgeTraceContext?
        var numericAttributes: [String: Double] = [:]

        switch event {
        case .started(let retainedSubscriptions, let eventTraceContext):
            phase = "review_metadata_publication_started"
            result = "started"
            resultReason = "none"
            traceContext = eventTraceContext
            numericAttributes["agentstudio.bridge.review.publication.retained"] =
                Double(retainedSubscriptions)
        case .completed(let receipt, let eventTraceContext):
            phase = "review_metadata_publication_completed"
            result = "success"
            resultReason = "none"
            traceContext = eventTraceContext
            numericAttributes["agentstudio.bridge.review.publication.retained"] =
                Double(receipt.retained)
            numericAttributes["agentstudio.bridge.review.publication.published_subscriptions"] =
                Double(receipt.publishedSubscriptions)
            numericAttributes["agentstudio.bridge.review.publication.emitted_events"] =
                Double(receipt.emittedEvents)
            numericAttributes["agentstudio.bridge.review.publication.superseded"] =
                Double(receipt.superseded)
        case .failed(let failure, let retainedSubscriptions, let eventTraceContext):
            phase = "review_metadata_publication_failed"
            result = "failure"
            resultReason = failure.rawValue
            traceContext = eventTraceContext
            numericAttributes["agentstudio.bridge.review.publication.retained"] =
                Double(retainedSubscriptions)
        }

        await recorder.record(
            sample: BridgeTelemetrySample(
                scope: .swift,
                name: "performance.bridge.swift.review_metadata_publication",
                durationMilliseconds: nil,
                traceContext: traceContext,
                stringAttributes: [
                    "agentstudio.bridge.phase": phase,
                    "agentstudio.bridge.plane": BridgeTelemetryPlane.data.rawValue,
                    "agentstudio.bridge.priority": BridgeTelemetryPriority.hot.rawValue,
                    "agentstudio.bridge.protocol": "review",
                    "agentstudio.bridge.result": result,
                    "agentstudio.bridge.result_reason": resultReason,
                    "agentstudio.bridge.slice": BridgeTelemetrySlice.reviewMetadata.rawValue,
                    "agentstudio.bridge.transport": "swift",
                    "agentstudio.bridge.viewer": "review",
                ],
                numericAttributes: numericAttributes,
                booleanAttributes: [:]
            ),
            receivedAtUnixNano: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
    }
}
