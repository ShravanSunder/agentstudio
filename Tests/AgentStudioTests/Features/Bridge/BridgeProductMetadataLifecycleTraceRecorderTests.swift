import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product metadata lifecycle trace recorder")
struct BridgeProductMetadataLifecycleTraceRecorderTests {
    @Test("File window enqueue maps to the typed native telemetry vocabulary")
    func fileWindowEnqueueMapsToTypedTelemetryVocabulary() async throws {
        // Arrange
        let sink = BridgeProductMetadataLifecycleTraceSink()
        let recorder = BridgeProductMetadataLifecycleTraceRecorder(recorder: sink)
        let traceContext = try BridgeTraceContext(
            traceId: "11111111111111111111111111111111",
            spanId: "2222222222222222",
            parentSpanId: nil,
            sampled: true
        )

        // Act
        await recorder.record(
            .init(
                stage: .windowEnqueued,
                subscriptionKind: .fileMetadata,
                result: .queued,
                traceContext: traceContext,
                sourceGeneration: 7,
                rowCount: 256,
                isFinalWindow: false
            )
        )

        // Assert
        let sample = try #require(await sink.recordedSamples().only)
        #expect(sample.scope == .swift)
        #expect(sample.name == "performance.bridge.swift.metadata_bootstrap_lifecycle")
        #expect(sample.traceContext == traceContext)
        #expect(
            sample.stringAttributes == [
                "agentstudio.bridge.phase": "metadata_window_enqueued",
                "agentstudio.bridge.plane": "data",
                "agentstudio.bridge.priority": "hot",
                "agentstudio.bridge.protocol": "worktree-file",
                "agentstudio.bridge.result": "queued",
                "agentstudio.bridge.slice": "tree_prepare_input",
                "agentstudio.bridge.transport": "swift",
                "agentstudio.bridge.viewer": "file",
            ]
        )
        #expect(sample.numericAttributes["agentstudio.bridge.source.generation"] == 7)
        #expect(sample.numericAttributes["agentstudio.bridge.worktree_file.tree.window.row.count"] == 256)
        #expect(
            sample.booleanAttributes["agentstudio.bridge.worktree_file.tree.window.is_final"] == false
        )
    }

    @Test("Review lifecycle stages cannot inherit File-only window fields")
    func reviewLifecycleStageOmitsFileWindowFields() async throws {
        // Arrange
        let sink = BridgeProductMetadataLifecycleTraceSink()
        let recorder = BridgeProductMetadataLifecycleTraceRecorder(recorder: sink)

        // Act
        await recorder.record(
            .init(
                stage: .sourceAcceptedEnqueued,
                subscriptionKind: .reviewMetadata,
                result: .queued,
                traceContext: nil,
                sourceGeneration: 9
            )
        )

        // Assert
        let sample = try #require(await sink.recordedSamples().only)
        #expect(sample.stringAttributes["agentstudio.bridge.protocol"] == "review")
        #expect(sample.stringAttributes["agentstudio.bridge.viewer"] == "review")
        #expect(sample.stringAttributes["agentstudio.bridge.slice"] == "review_metadata")
        #expect(sample.numericAttributes["agentstudio.bridge.source.generation"] == 9)
        #expect(sample.numericAttributes["agentstudio.bridge.worktree_file.tree.window.row.count"] == nil)
        #expect(sample.booleanAttributes.isEmpty)
    }

    @Test("Review publication started and completed events preserve typed receipt accounting")
    func reviewPublicationLifecyclePreservesReceiptAccounting() async throws {
        // Arrange
        let sink = BridgeProductMetadataLifecycleTraceSink()
        let recorder = BridgeProductMetadataLifecycleTraceRecorder(recorder: sink)
        let traceContext = try BridgeTraceContext(
            traceId: "33333333333333333333333333333333",
            spanId: "4444444444444444",
            parentSpanId: nil,
            sampled: true
        )
        let receipt = BridgeReviewMetadataPublicationReceipt(
            retained: 2,
            publishedSubscriptions: 1,
            emittedEvents: 3,
            superseded: 1
        )

        // Act
        await recorder.record(
            BridgeProductReviewMetadataPublicationTraceEvent.started(
                retainedSubscriptions: 2,
                traceContext: traceContext
            )
        )
        await recorder.record(
            BridgeProductReviewMetadataPublicationTraceEvent.completed(
                receipt: receipt,
                traceContext: traceContext
            )
        )

        // Assert
        let samples = await sink.recordedSamples()
        #expect(samples.count == 2)
        let started = try #require(samples.first)
        #expect(started.name == "performance.bridge.swift.review_metadata_publication")
        #expect(started.traceContext == traceContext)
        #expect(started.stringAttributes["agentstudio.bridge.phase"] == "review_metadata_publication_started")
        #expect(started.stringAttributes["agentstudio.bridge.result"] == "started")
        #expect(started.stringAttributes["agentstudio.bridge.result_reason"] == "none")
        #expect(started.stringAttributes["agentstudio.bridge.protocol"] == "review")
        #expect(started.stringAttributes["agentstudio.bridge.viewer"] == "review")
        #expect(started.numericAttributes["agentstudio.bridge.review.publication.retained"] == 2)

        let completed = try #require(samples.last)
        #expect(completed.name == "performance.bridge.swift.review_metadata_publication")
        #expect(completed.traceContext == traceContext)
        #expect(completed.stringAttributes["agentstudio.bridge.phase"] == "review_metadata_publication_completed")
        #expect(completed.stringAttributes["agentstudio.bridge.result"] == "success")
        #expect(completed.stringAttributes["agentstudio.bridge.result_reason"] == "none")
        #expect(completed.numericAttributes["agentstudio.bridge.review.publication.retained"] == 2)
        #expect(completed.numericAttributes["agentstudio.bridge.review.publication.published_subscriptions"] == 1)
        #expect(completed.numericAttributes["agentstudio.bridge.review.publication.emitted_events"] == 3)
        #expect(completed.numericAttributes["agentstudio.bridge.review.publication.superseded"] == 1)
    }

    @Test("Review publication failures retain distinct closed reason vocabulary")
    func reviewPublicationFailuresRetainDistinctReasons() async throws {
        // Arrange
        let sink = BridgeProductMetadataLifecycleTraceSink()
        let recorder = BridgeProductMetadataLifecycleTraceRecorder(recorder: sink)
        let expectedReasons: [(BridgeProductReviewMetadataPublicationFailure, String)] = [
            (.cancellation, "cancellation"),
            (.eventConstruction, "event_construction"),
            (.producerQueueReset, "producer_queue_reset"),
            (.producerRejection, "producer_rejection"),
            (.resetEnqueueFailure, "reset_enqueue_failure"),
            (.unexpected, "unexpected"),
        ]

        // Act
        for (failure, _) in expectedReasons {
            await recorder.record(
                BridgeProductReviewMetadataPublicationTraceEvent.failed(
                    failure: failure,
                    retainedSubscriptions: 1,
                    traceContext: nil
                )
            )
        }

        // Assert
        let samples = await sink.recordedSamples()
        #expect(samples.count == expectedReasons.count)
        for (sample, expected) in zip(samples, expectedReasons) {
            #expect(sample.name == "performance.bridge.swift.review_metadata_publication")
            #expect(sample.stringAttributes["agentstudio.bridge.phase"] == "review_metadata_publication_failed")
            #expect(sample.stringAttributes["agentstudio.bridge.result"] == "failure")
            #expect(sample.stringAttributes["agentstudio.bridge.result_reason"] == expected.1)
            #expect(sample.stringAttributes["agentstudio.bridge.protocol"] == "review")
            #expect(sample.stringAttributes["agentstudio.bridge.viewer"] == "review")
            #expect(sample.numericAttributes["agentstudio.bridge.review.publication.retained"] == 1)
        }
    }

    @Test("producer bootstrap failures map a closed typed reason vocabulary")
    func producerBootstrapFailuresMapClosedTypedReasons() async throws {
        // Arrange
        let sink = BridgeProductMetadataLifecycleTraceSink()
        let recorder = BridgeProductMetadataLifecycleTraceRecorder(recorder: sink)
        let expectedReasons: [(BridgeProductMetadataProducerFailureReason, String)] = [
            (.reviewEventConstruction, "review_event_construction"),
            (.producerQueueReset, "producer_queue_reset"),
            (.producerRejection(.unknownLease), "producer_rejection_unknown_lease"),
            (.sessionEnqueueFailure, "session_enqueue_failure"),
            (.unexpected, "unexpected"),
            (.cancellation, "cancellation"),
            (.taskCancellation, "task_cancellation"),
        ]

        // Act
        for (failureReason, _) in expectedReasons {
            await recorder.record(
                .init(
                    stage: failureReason == .taskCancellation ? .producerCancelled : .producerFailed,
                    subscriptionKind: .reviewMetadata,
                    result: .failure,
                    failureReason: failureReason,
                    traceContext: nil
                )
            )
        }

        // Assert
        let samples = await sink.recordedSamples()
        #expect(samples.count == expectedReasons.count)
        for (sample, expected) in zip(samples, expectedReasons) {
            #expect(sample.name == "performance.bridge.swift.metadata_bootstrap_lifecycle")
            #expect(sample.stringAttributes["agentstudio.bridge.result"] == "failure")
            #expect(sample.stringAttributes["agentstudio.bridge.result_reason"] == expected.1)
            #expect(sample.stringAttributes["agentstudio.bridge.protocol"] == "review")
        }
    }
}

private actor BridgeProductMetadataLifecycleTraceSink: BridgePerformanceTraceRecording {
    private var samples: [BridgeTelemetrySample] = []

    func record(sample: BridgeTelemetrySample, receivedAtUnixNano _: UInt64) {
        samples.append(sample)
    }

    func recordDrop(
        reason _: BridgeTelemetryDropReason,
        droppedCount _: Int,
        firstRejectedEventName _: String?,
        receivedAtUnixNano _: UInt64
    ) {}

    func drain() {}

    func recordedSamples() -> [BridgeTelemetrySample] {
        samples
    }
}

extension Array {
    fileprivate var only: Element? {
        count == 1 ? self[0] : nil
    }
}
