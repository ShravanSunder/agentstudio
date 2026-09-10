import AgentStudioInfrastructure
import Testing

@testable import AgentStudioBridge

@Suite("Bridge telemetry native rejection diagnostics")
struct BridgeTelemetryNativeProjectorRejectionTests {
    @Test("reports a scrubbed rejection through the existing drop recorder")
    func reportsScrubbedRejectedEvent() async throws {
        // Arrange — an untrusted event name must not enter diagnostic output.
        let recorder = RejectionRecorder()
        let projector = BridgeTelemetryNativeProjector(recorder: recorder)
        let batch = BridgeTelemetryBatchRequest(
            telemetrySessionId: "telemetry-rejection-test",
            batchSequence: 1,
            samples: [
                .init(
                    producerId: .main,
                    producerSequence: 1,
                    sample: .requiredEvent(
                        .init(
                            timestampMilliseconds: 1,
                            sample: BridgeTelemetrySample(
                                scope: .web,
                                name: "untrusted-private-event-name",
                                durationMilliseconds: nil,
                                traceContext: nil,
                                stringAttributes: [:],
                                numericAttributes: [:],
                                booleanAttributes: [:]
                            )
                        )
                    )
                )
            ],
            lossSummaries: []
        )

        // Act — rejection remains fail-closed.
        await #expect(throws: BridgeTelemetryNativeProjectorError.invalidSample) {
            _ = try await projector.project(batch)
        }

        // Assert — diagnostics identify the category, never the untrusted name.
        #expect(await recorder.recordedSampleCount == 0)
        #expect(await recorder.reasons == [.unsafeEventName])
        #expect(await recorder.rejectedEventNames == ["unknown"])
        #expect(await recorder.droppedCounts == [1])
    }
}

private actor RejectionRecorder: BridgePerformanceTraceRecording {
    private(set) var recordedSampleCount = 0
    private(set) var reasons: [BridgeTelemetryDropReason] = []
    private(set) var rejectedEventNames: [String?] = []
    private(set) var droppedCounts: [Int] = []

    func record(sample _: BridgeTelemetrySample, receivedAtUnixNano _: UInt64) async {
        recordedSampleCount += 1
    }

    func recordDrop(
        reason: BridgeTelemetryDropReason,
        droppedCount: Int,
        firstRejectedEventName: String?,
        receivedAtUnixNano _: UInt64
    ) async {
        reasons.append(reason)
        rejectedEventNames.append(firstRejectedEventName)
        droppedCounts.append(droppedCount)
    }

    func drain() async throws {}
}
