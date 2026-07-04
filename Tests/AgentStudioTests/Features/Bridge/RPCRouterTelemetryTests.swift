import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class RPCRouterTelemetryTests {
    private actor BridgeTelemetryRecorderSpy: BridgePerformanceTraceRecording {
        private var recordedSamples: [BridgeTelemetrySample] = []

        func record(sample: BridgeTelemetrySample, receivedAtUnixNano: UInt64) async {
            recordedSamples.append(sample)
        }

        func recordDrop(
            reason: BridgeTelemetryDropReason,
            droppedCount: Int,
            firstRejectedEventName: String?,
            receivedAtUnixNano: UInt64
        ) async {
            _ = reason
            _ = droppedCount
            _ = firstRejectedEventName
            _ = receivedAtUnixNano
        }

        func samples() -> [BridgeTelemetrySample] {
            recordedSamples
        }

        func drain() async throws {}
    }

    private actor BridgeTelemetryIngestorSpy: BridgeTelemetryBatchIngesting {
        private var ingestCount = 0

        func ingest(_ data: Data) async -> BridgeTelemetryIngestResult {
            ingestCount += 1
            return .accepted(sampleCount: 1)
        }

        func count() -> Int {
            ingestCount
        }
    }

    private actor BlockingBridgeTelemetryIngestorSpy: BridgeTelemetryBatchIngesting {
        private let blockingFirstBatchCount: Int
        private var ingestCount = 0
        private var blockedContinuations: [CheckedContinuation<BridgeTelemetryIngestResult, Never>] = []
        private var ingestCountWaiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []

        init(blockingFirstBatchCount: Int) {
            self.blockingFirstBatchCount = blockingFirstBatchCount
        }

        func ingest(_ data: Data) async -> BridgeTelemetryIngestResult {
            ingestCount += 1
            resumeSatisfiedWaiters()
            guard ingestCount <= blockingFirstBatchCount else {
                return .accepted(sampleCount: 1)
            }
            return await withCheckedContinuation { continuation in
                blockedContinuations.append(continuation)
            }
        }

        func waitForIngestCount(_ target: Int) async {
            guard ingestCount < target else {
                return
            }
            await withCheckedContinuation { continuation in
                ingestCountWaiters.append((target: target, continuation: continuation))
            }
        }

        func releaseAll(sampleCount: Int = 1) {
            let continuations = blockedContinuations
            blockedContinuations.removeAll()
            for continuation in continuations {
                continuation.resume(returning: .accepted(sampleCount: sampleCount))
            }
        }

        func count() -> Int {
            ingestCount
        }

        private func resumeSatisfiedWaiters() {
            let readyWaiters = ingestCountWaiters.filter { $0.target <= ingestCount }
            ingestCountWaiters.removeAll { $0.target <= ingestCount }
            for waiter in readyWaiters {
                waiter.continuation.resume()
            }
        }
    }

    @Test
    func telemetry_queue_keeps_best_effort_shallow_while_allowing_bounded_prioritized_burst() {
        // Arrange
        var bestEffortQueue = BridgeTelemetryQueue()
        var warmQueue = BridgeTelemetryQueue()

        // Act / Assert
        for _ in 0..<BridgeTelemetryLimits.maxPendingBatchesPerPane {
            #expect(bestEffortQueue.admitBatch(priority: .bestEffort) == nil)
        }
        #expect(bestEffortQueue.admitBatch(priority: .bestEffort) == .queueSaturated)

        for _ in 0..<BridgeTelemetryLimits.maxPrioritizedPendingBatchesPerPane {
            #expect(warmQueue.admitBatch(priority: .warm) == nil)
        }
        #expect(warmQueue.admitBatch(priority: .warm) == .queueSaturated)
    }

    @Test
    func oversized_bridge_telemetry_rpc_records_drop_before_rejection() async {
        // Arrange
        let router = RPCRouter()
        let recorder = BridgeTelemetryRecorderSpy()
        let ingestor = BridgeTelemetryIngestorSpy()
        router.telemetryRecorder = recorder
        router.telemetryIngestor = ingestor
        var errorCode: Int?
        router.onError = { code, _, _ in errorCode = code }
        let oversizedBody = String(
            repeating: "a",
            count: BridgeTelemetryLimits.maxEncodedBatchBytes
        )

        // Act
        await router.dispatch(
            json:
                #"{"jsonrpc":"2.0","method":"system.bridgeTelemetry","params":{"schemaVersion":1,"scenario":"test","samples":[],"body":""#
                + oversizedBody
                + #""}}"#,
            isBridgeReady: true
        )

        // Assert
        #expect(errorCode == -32_602)
        #expect(await ingestor.count() == 0)
        let telemetryBatch = await recorder.samples().first
        #expect(telemetryBatch?.name == "performance.bridge.webkit.telemetry_batch")
        #expect(
            telemetryBatch?.stringAttributes["agentstudio.bridge.telemetry.drop_reason"]
                == BridgeTelemetryDropReason.encodedBatchTooLarge.rawValue
        )
        #expect(telemetryBatch?.stringAttributes["agentstudio.bridge.plane"] == "observability")
        #expect(telemetryBatch?.stringAttributes["agentstudio.bridge.priority"] == "best_effort")
        #expect(telemetryBatch?.stringAttributes["agentstudio.bridge.slice"] == "telemetry_batch")
    }

    @Test
    func hot_bridge_telemetry_batch_is_admitted_when_best_effort_batches_are_pending() async throws {
        // Arrange
        let router = RPCRouter()
        let recorder = BridgeTelemetryRecorderSpy()
        let ingestor = BlockingBridgeTelemetryIngestorSpy(blockingFirstBatchCount: 2)
        router.telemetryRecorder = recorder
        router.telemetryIngestor = ingestor
        var errorCodes: [Int] = []
        router.onError = { code, _, _ in
            errorCodes.append(code)
        }

        let firstBestEffortRPC = try Self.makeTelemetryRPC(
            sampleName: "performance.bridge.web.telemetry_drop",
            priority: .bestEffort,
            stringAttributes: Self.telemetryDropStringAttributes(),
            numericAttributes: ["agentstudio.bridge.telemetry.dropped_count": 1]
        )
        let secondBestEffortRPC = try Self.makeTelemetryRPC(
            sampleName: "performance.bridge.web.telemetry_drop",
            priority: .bestEffort,
            stringAttributes: Self.telemetryDropStringAttributes(),
            numericAttributes: ["agentstudio.bridge.telemetry.dropped_count": 1]
        )
        let hotStartupRPC = try Self.makeTelemetryRPC(
            sampleName: "performance.bridge.web.review_metadata_apply",
            priority: .hot,
            stringAttributes: Self.reviewMetadataApplyStringAttributes(),
            numericAttributes: ["agentstudio.bridge.review.item_count": 12]
        )

        // Act
        async let firstDispatch: Void = router.dispatch(json: firstBestEffortRPC, isBridgeReady: true)
        async let secondDispatch: Void = router.dispatch(json: secondBestEffortRPC, isBridgeReady: true)
        await ingestor.waitForIngestCount(2)
        await router.dispatch(json: hotStartupRPC, isBridgeReady: true)
        await ingestor.releaseAll()
        _ = await (firstDispatch, secondDispatch)

        // Assert
        #expect(errorCodes.isEmpty)
        #expect(await ingestor.count() == 3)
        let telemetryBatchSamples = await recorder.samples()
            .filter { $0.name == "performance.bridge.webkit.telemetry_batch" }
        #expect(telemetryBatchSamples.count == 3)
        #expect(
            telemetryBatchSamples.allSatisfy {
                $0.stringAttributes["agentstudio.bridge.phase"] == "accepted"
            }
        )
    }

    @Test
    func warm_control_telemetry_batch_is_admitted_when_best_effort_batches_are_pending() async throws {
        // Arrange
        let router = RPCRouter()
        let recorder = BridgeTelemetryRecorderSpy()
        let ingestor = BlockingBridgeTelemetryIngestorSpy(blockingFirstBatchCount: 2)
        router.telemetryRecorder = recorder
        router.telemetryIngestor = ingestor
        var errorCodes: [Int] = []
        router.onError = { code, _, _ in
            errorCodes.append(code)
        }

        let firstBestEffortRPC = try Self.makeTelemetryRPC(
            sampleName: "performance.bridge.web.telemetry_drop",
            priority: .bestEffort,
            stringAttributes: Self.telemetryDropStringAttributes(),
            numericAttributes: ["agentstudio.bridge.telemetry.dropped_count": 1]
        )
        let secondBestEffortRPC = try Self.makeTelemetryRPC(
            sampleName: "performance.bridge.web.telemetry_drop",
            priority: .bestEffort,
            stringAttributes: Self.telemetryDropStringAttributes(),
            numericAttributes: ["agentstudio.bridge.telemetry.dropped_count": 1]
        )
        let warmControlRPC = try Self.makeTelemetryRPC(
            sampleName: "performance.bridge.web.rpc_send",
            priority: .warm,
            stringAttributes: Self.rpcSendStringAttributes(),
            numericAttributes: [:]
        )

        // Act
        async let firstDispatch: Void = router.dispatch(json: firstBestEffortRPC, isBridgeReady: true)
        async let secondDispatch: Void = router.dispatch(json: secondBestEffortRPC, isBridgeReady: true)
        await ingestor.waitForIngestCount(2)
        await router.dispatch(json: warmControlRPC, isBridgeReady: true)
        await ingestor.releaseAll()
        _ = await (firstDispatch, secondDispatch)

        // Assert
        #expect(errorCodes.isEmpty)
        #expect(await ingestor.count() == 3)
        let telemetryBatchSamples = await recorder.samples()
            .filter { $0.name == "performance.bridge.webkit.telemetry_batch" }
        #expect(telemetryBatchSamples.count == 3)
        #expect(
            telemetryBatchSamples.allSatisfy {
                $0.stringAttributes["agentstudio.bridge.phase"] == "accepted"
            }
        )
    }

    private static func makeTelemetryRPC(
        sampleName: String,
        priority: BridgeTelemetryPriority,
        stringAttributes: [String: String],
        numericAttributes: [String: Double]
    ) throws -> String {
        var attributes = stringAttributes
        attributes["agentstudio.bridge.priority"] = priority.rawValue
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "test",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: sampleName,
                    durationMilliseconds: 1,
                    traceContext: nil,
                    stringAttributes: attributes,
                    numericAttributes: numericAttributes,
                    booleanAttributes: [:]
                )
            ]
        )
        let paramsData = try JSONEncoder().encode(batch)
        let paramsJSON = try #require(String(data: paramsData, encoding: .utf8))
        return #"{"jsonrpc":"2.0","method":"system.bridgeTelemetry","params":\#(paramsJSON)}"#
    }

    private static func telemetryDropStringAttributes() -> [String: String] {
        [
            "agentstudio.bridge.phase": "dropped",
            "agentstudio.bridge.plane": BridgeTelemetryPlane.observability.rawValue,
            "agentstudio.bridge.slice": BridgeTelemetrySlice.telemetryDrop.rawValue,
            "agentstudio.bridge.telemetry.drop_reason": BridgeTelemetryDropReason.queueSaturated.rawValue,
            "agentstudio.bridge.transport": "rpc",
        ]
    }

    private static func reviewMetadataApplyStringAttributes() -> [String: String] {
        [
            "agentstudio.bridge.phase": "review_metadata_apply",
            "agentstudio.bridge.plane": BridgeTelemetryPlane.data.rawValue,
            "agentstudio.bridge.result": "success",
            "agentstudio.bridge.slice": BridgeTelemetrySlice.reviewMetadata.rawValue,
            "agentstudio.bridge.transport": "intake",
        ]
    }

    private static func rpcSendStringAttributes() -> [String: String] {
        [
            "agentstudio.bridge.phase": "send",
            "agentstudio.bridge.plane": BridgeTelemetryPlane.control.rawValue,
            "agentstudio.bridge.rpc.method_class": "review",
            "agentstudio.bridge.slice": BridgeTelemetrySlice.reviewRPC.rawValue,
            "agentstudio.bridge.transport": "rpc",
        ]
    }
}
