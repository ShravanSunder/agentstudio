import Foundation
import Testing

@testable import AgentStudio

@Suite
struct BridgeTelemetryBatchValidatorSequenceTests {
    @Test
    func sequenceGapRequiresMatchingDropCounter() throws {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let firstBatchData = try Self.batchData(sequence: 1, sample: Self.rpcSendSample)
        let gapWithoutCounterData = try Self.batchData(sequence: 3, sample: Self.rpcSendSample)
        let gapWithCounterData = try Self.batchData(sequence: 3, sample: Self.telemetryDropSample)
        let gapWithRequiredShedCounterData = try Self.batchData(
            sequence: 5,
            samples: [
                Self.telemetryDropSample,
                Self.requiredEventShedTelemetryDropSample,
            ]
        )

        #expect(Self.validationDescription(validator.decodeAndValidate(firstBatchData)) == "accepted")
        #expect(
            Self.validationDescription(validator.decodeAndValidate(gapWithoutCounterData))
                == "dropped:missing_drop_counter"
        )
        #expect(Self.validationDescription(validator.decodeAndValidate(gapWithCounterData)) == "accepted")
        #expect(
            Self.validationDescription(validator.decodeAndValidate(gapWithRequiredShedCounterData))
                == "dropped:required_event_shed"
        )
    }

    @Test
    func telemetryBatchRequiresStreamId() throws {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let legacyBatchData = try Self.legacyBatchDataWithoutStreamId(
            sequence: 1,
            sample: Self.rpcSendSample
        )

        #expect(
            Self.validationDescription(validator.decodeAndValidate(legacyBatchData))
                == "dropped:decoding_failed"
        )
    }

    @Test
    func batchSequencesAreIndependentPerTelemetryStream() throws {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let firstPageBatchData = try Self.batchData(
            streamId: "page",
            sequence: 1,
            sample: Self.rpcSendSample
        )
        let firstWorkerBatchData = try Self.batchData(
            streamId: "comm-worker",
            sequence: 1,
            sample: Self.workerTaskSample
        )
        let pageGapWithoutCounterData = try Self.batchData(
            streamId: "page",
            sequence: 3,
            sample: Self.rpcSendSample
        )

        #expect(Self.validationDescription(validator.decodeAndValidate(firstPageBatchData)) == "accepted")
        #expect(Self.validationDescription(validator.decodeAndValidate(firstWorkerBatchData)) == "accepted")
        #expect(
            Self.validationDescription(validator.decodeAndValidate(pageGapWithoutCounterData))
                == "dropped:missing_drop_counter"
        )
    }

    private static var rpcSendSample: BridgeTelemetrySample {
        batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.rpc_send",
                phase: "send",
                plane: "control",
                priority: "warm",
                slice: "review_rpc",
                transport: "rpc",
                extraStrings: ["agentstudio.bridge.rpc.method_class": "review"]
            )
        ).samples[0]
    }

    private static var telemetryDropSample: BridgeTelemetrySample {
        batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.telemetry_drop",
                phase: "dropped",
                plane: "observability",
                priority: "best_effort",
                slice: "telemetry_drop",
                transport: "scheme",
                extraStrings: [
                    "agentstudio.bridge.telemetry.drop_reason": "encoded_byte_cap",
                    "agentstudio.bridge.telemetry.event_name": "performance.bridge.web.rpc_send",
                    "agentstudio.bridge.telemetry.lane": "warm",
                    "agentstudio.bridge.telemetry.result": "success",
                ],
                extraNumbers: ["agentstudio.bridge.telemetry.dropped_count": 1]
            )
        ).samples[0]
    }

    private static var requiredEventShedTelemetryDropSample: BridgeTelemetrySample {
        batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.telemetry_drop",
                phase: "dropped",
                plane: "observability",
                priority: "best_effort",
                slice: "telemetry_drop",
                transport: "scheme",
                extraStrings: [
                    "agentstudio.bridge.telemetry.drop_reason": "required_event_shed"
                ],
                extraNumbers: ["agentstudio.bridge.telemetry.dropped_count": 1]
            )
        ).samples[0]
    }

    private static var workerTaskSample: BridgeTelemetrySample {
        batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.worker.task",
                phase: "worker_task",
                plane: "data",
                priority: "hot",
                slice: "worker_task",
                transport: "worker",
                extraStrings: [
                    "agentstudio.bridge.result": "success",
                    "agentstudio.bridge.worker.command": "select",
                    "agentstudio.bridge.worker.lane": "selected",
                    "agentstudio.bridge.worker.task_kind": "message_handler",
                ],
                extraNumbers: [
                    "agentstudio.bridge.worker.handler_duration_ms": 1,
                    "agentstudio.bridge.worker.queue_wait_ms": 0,
                ]
            )
        ).samples[0]
    }

    private static func batchData(sequence: Int, sample: BridgeTelemetrySample) throws -> Data {
        try batchData(sequence: sequence, samples: [sample])
    }

    private static func batchData(
        streamId: String,
        sequence: Int,
        sample: BridgeTelemetrySample
    ) throws -> Data {
        try batchData(streamId: streamId, sequence: sequence, samples: [sample])
    }

    private static func batchData(sequence: Int, samples: [BridgeTelemetrySample]) throws -> Data {
        try batchData(streamId: "page", sequence: sequence, samples: samples)
    }

    private static func batchData(
        streamId: String,
        sequence: Int,
        samples: [BridgeTelemetrySample]
    ) throws -> Data {
        try JSONEncoder().encode(
            TelemetryBatchFixture(
                schemaVersion: 1,
                scenario: "bridge-runtime",
                streamId: streamId,
                sequence: sequence,
                samples: samples
            )
        )
    }

    private static func legacyBatchDataWithoutStreamId(
        sequence: Int,
        sample: BridgeTelemetrySample
    ) throws -> Data {
        try JSONEncoder().encode(
            LegacyTelemetryBatchFixture(
                schemaVersion: 1,
                scenario: "bridge-runtime",
                sequence: sequence,
                samples: [sample]
            )
        )
    }

    private struct TelemetryBatchFixture: Encodable {
        let schemaVersion: Int
        let scenario: String
        let streamId: String
        let sequence: Int
        let samples: [BridgeTelemetrySample]
    }

    private struct LegacyTelemetryBatchFixture: Encodable {
        let schemaVersion: Int
        let scenario: String
        let sequence: Int
        let samples: [BridgeTelemetrySample]
    }

    private static func validationDescription(_ result: BridgeTelemetryBatchValidationResult) -> String {
        switch result {
        case .accepted:
            "accepted"
        case .dropped(let reason):
            "dropped:\(reason.rawValue)"
        }
    }
}
