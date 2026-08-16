import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite
struct BridgeComparisonCatalogTraceRecorderTests {
    @Test("comparison catalog trace submission does not wait for recorder completion")
    func traceSubmissionDoesNotWaitForRecorderCompletion() async {
        let recorder = HeldComparisonTargetCatalogTraceRecorder()
        let event = BridgeReviewComparisonTargetCatalogTraceEvent(
            stage: .authorization,
            outcome: .success,
            queryRequestSequence: 1,
            durationMilliseconds: 1,
            reservationAgeMilliseconds: nil,
            inputRowCount: nil,
            outputRowCount: nil,
            observedByteCount: nil,
            isTruncated: nil
        )

        recorder.submit(event)
        let submittedEvent = await recorder.waitUntilRecordingStarted()

        #expect(submittedEvent == event)
        await recorder.release()
    }

    @Test("comparison catalog trace recorder projects controlled aggregate fields")
    func recorderProjectsControlledAggregateFields() async throws {
        let sink = ComparisonTargetCatalogSampleSink()
        let recorder = BridgeReviewComparisonTargetCatalogTraceRecorder(
            recorder: sink,
            timeUnixNano: { 123 }
        )

        await recorder.record(
            BridgeReviewComparisonTargetCatalogTraceEvent(
                stage: .encode,
                outcome: .success,
                queryRequestSequence: 7,
                durationMilliseconds: 4,
                reservationAgeMilliseconds: nil,
                inputRowCount: 3,
                outputRowCount: 2,
                observedByteCount: 512,
                isTruncated: true
            )
        )

        let record = try #require(await sink.records.first)
        #expect(record.receivedAtUnixNano == 123)
        #expect(record.sample.scope == .swift)
        #expect(record.sample.name == "performance.bridge.swift.comparison_target_catalog")
        #expect(record.sample.durationMilliseconds == 4)
        #expect(record.sample.traceContext == nil)
        #expect(
            record.sample.stringAttributes == [
                "agentstudio.bridge.phase": "encode",
                "agentstudio.bridge.plane": "data",
                "agentstudio.bridge.priority": "cold",
                "agentstudio.bridge.result": "success",
                "agentstudio.bridge.result_reason": "none",
                "agentstudio.bridge.slice": "content_fetch",
                "agentstudio.bridge.transport": "swift",
                "agentstudio.bridge.viewer": "review",
            ])
        #expect(
            record.sample.numericAttributes == [
                "agentstudio.bridge.content.byte_count": 512,
                "agentstudio.bridge.review.comparison_targets.input_row.count": 3,
                "agentstudio.bridge.review.comparison_targets.output_row.count": 2,
                "agentstudio.bridge.review.comparison_targets.query_request.sequence": 7,
            ])
        #expect(
            record.sample.booleanAttributes == [
                "agentstudio.bridge.review.comparison_targets.is_truncated": true
            ])
    }

    @Test("claim trace records reservation age without raw request identity")
    func claimTraceRecordsReservationAgeWithoutRawRequestIdentity() async throws {
        let sink = ComparisonTargetCatalogSampleSink()
        let recorder = BridgeReviewComparisonTargetCatalogTraceRecorder(
            recorder: sink,
            timeUnixNano: { 456 }
        )

        await recorder.record(
            BridgeReviewComparisonTargetCatalogTraceEvent(
                stage: .reservationClaim,
                outcome: .claimed,
                queryRequestSequence: 9,
                durationMilliseconds: nil,
                reservationAgeMilliseconds: 12,
                inputRowCount: nil,
                outputRowCount: nil,
                observedByteCount: nil,
                isTruncated: nil
            )
        )

        let sample = try #require(await sink.records.first?.sample)
        #expect(sample.stringAttributes["agentstudio.bridge.phase"] == "reservation_claim")
        #expect(sample.stringAttributes["agentstudio.bridge.result"] == "claimed")
        #expect(
            sample.numericAttributes == [
                "agentstudio.bridge.review.comparison_targets.query_request.sequence": 9,
                "agentstudio.bridge.review.comparison_targets.reservation_age_ms": 12,
            ])
        let allKeys = Set(sample.stringAttributes.keys)
            .union(sample.numericAttributes.keys)
            .union(sample.booleanAttributes.keys)
        #expect(
            !allKeys.contains { key in
                key.contains("descriptor") || key.contains("pane") || key.contains("worker")
            })
    }
}

private actor HeldComparisonTargetCatalogTraceRecorder:
    BridgeReviewComparisonTargetCatalogTraceRecording
{
    private var recordingStartedContinuation: CheckedContinuation<BridgeReviewComparisonTargetCatalogTraceEvent, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var recordedEvent: BridgeReviewComparisonTargetCatalogTraceEvent?

    func record(_ event: BridgeReviewComparisonTargetCatalogTraceEvent) async {
        recordedEvent = event
        recordingStartedContinuation?.resume(returning: event)
        recordingStartedContinuation = nil
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilRecordingStarted() async -> BridgeReviewComparisonTargetCatalogTraceEvent {
        if let recordedEvent { return recordedEvent }
        return await withCheckedContinuation { continuation in
            recordingStartedContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor ComparisonTargetCatalogSampleSink: BridgePerformanceTraceRecording {
    struct Record: Sendable {
        let sample: BridgeTelemetrySample
        let receivedAtUnixNano: UInt64
    }

    private(set) var records: [Record] = []

    func record(sample: BridgeTelemetrySample, receivedAtUnixNano: UInt64) {
        records.append(Record(sample: sample, receivedAtUnixNano: receivedAtUnixNano))
    }

    func recordDrop(
        reason: BridgeTelemetryDropReason,
        droppedCount: Int,
        firstRejectedEventName: String?,
        receivedAtUnixNano: UInt64
    ) {
        _ = (reason, droppedCount, firstRejectedEventName, receivedAtUnixNano)
    }

    func drain() {}
}
