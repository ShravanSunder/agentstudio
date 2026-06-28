import Foundation
import Testing

@testable import AgentStudio

@Suite
struct BridgeTelemetryReviewStartupValidatorTests {
    @Test
    func validatorAcceptsReviewStartupContentStreamTelemetry() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let acceptedBatches = [
            batchWithWebSample(
                WebSampleProps(
                    name: "performance.bridge.web.review_package_first_chunk",
                    phase: "review_package_first_chunk",
                    plane: "data",
                    priority: "hot",
                    slice: "review_snapshot",
                    transport: "content",
                    extraStrings: ["agentstudio.bridge.result": "success"],
                    extraNumbers: [
                        "agentstudio.bridge.content.chunk_byte_count": 65_536,
                        "agentstudio.bridge.content.total_bytes_read": 65_536,
                    ]
                )
            ),
            batchWithWebSample(
                WebSampleProps(
                    name: "performance.bridge.web.review_package_body_load",
                    phase: "review_package_body_load",
                    plane: "data",
                    priority: "hot",
                    slice: "review_snapshot",
                    transport: "content",
                    extraStrings: ["agentstudio.bridge.result": "success"],
                    extraNumbers: [
                        "agentstudio.bridge.content.byte_count": 1_356_525,
                        "agentstudio.bridge.content.chunk_count": 21,
                    ]
                )
            ),
            batchWithWebSample(
                WebSampleProps(
                    name: "performance.bridge.web.selected_content_ready",
                    phase: "selected_content_ready",
                    plane: "data",
                    priority: "hot",
                    slice: "content_fetch",
                    transport: "content",
                    extraStrings: ["agentstudio.bridge.result": "success"],
                    extraNumbers: ["agentstudio.bridge.content.resource_count": 2]
                )
            ),
        ]

        for batch in acceptedBatches {
            #expect(validator.validate(batch) == .accepted(batch))
        }
    }

    private struct WebSampleProps {
        let name: String
        let phase: String
        let plane: String
        let priority: String
        let slice: String
        let transport: String
        var extraStrings: [String: String] = [:]
        var extraNumbers: [String: Double] = [:]
    }

    private func batchWithWebSample(_ props: WebSampleProps) -> BridgeTelemetryBatch {
        var stringAttributes = [
            "agentstudio.bridge.phase": props.phase,
            "agentstudio.bridge.plane": props.plane,
            "agentstudio.bridge.priority": props.priority,
            "agentstudio.bridge.slice": props.slice,
            "agentstudio.bridge.transport": props.transport,
        ]
        stringAttributes.merge(props.extraStrings) { _, new in new }
        return BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "review_startup_content_stream_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: props.name,
                    durationMilliseconds: 1.25,
                    traceContext: nil,
                    stringAttributes: stringAttributes,
                    numericAttributes: props.extraNumbers,
                    booleanAttributes: [:]
                )
            ]
        )
    }
}
