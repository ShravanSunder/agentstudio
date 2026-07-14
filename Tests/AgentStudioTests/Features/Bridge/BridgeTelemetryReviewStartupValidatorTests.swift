import Foundation
import Testing

@testable import AgentStudio

@Suite
struct BridgeTelemetryReviewStartupValidatorTests {
    @Test
    func validatorAcceptsReviewStartupMetadataAndContentTelemetry() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let acceptedBatches = [
            sampleWithWebAttributes(
                WebSampleProps(
                    name: "performance.bridge.web.review_metadata_apply",
                    phase: "review_metadata_apply",
                    plane: "data",
                    priority: "hot",
                    slice: "review_metadata",
                    transport: "intake",
                    extraStrings: [
                        "agentstudio.bridge.result": "success",
                        "agentstudio.bridge.result_reason": "none",
                    ],
                    extraNumbers: ["agentstudio.bridge.review.item_count": 527]
                )
            ),
            sampleWithWebAttributes(
                WebSampleProps(
                    name: "performance.bridge.web.review_metadata_apply",
                    phase: "review_metadata_apply",
                    plane: "data",
                    priority: "hot",
                    slice: "review_metadata",
                    transport: "intake",
                    extraStrings: [
                        "agentstudio.bridge.result": "failed",
                        "agentstudio.bridge.result_reason": "snapshot_materializer_rejected",
                    ]
                )
            ),
            sampleWithWebAttributes(
                WebSampleProps(
                    name: "performance.bridge.web.selected_content_ready",
                    phase: "selected_content_ready",
                    plane: "data",
                    priority: "hot",
                    slice: "content_fetch",
                    transport: "content",
                    extraStrings: [
                        "agentstudio.bridge.result": "success",
                        "agentstudio.bridge.result_reason": "none",
                    ],
                    extraNumbers: ["agentstudio.bridge.content.resource_count": 2]
                )
            ),
            sampleWithWebAttributes(
                WebSampleProps(
                    name: "performance.bridge.web.selection_commit",
                    phase: "selection_commit",
                    plane: "data",
                    priority: "warm",
                    slice: "review_projection",
                    transport: "worker",
                    extraStrings: [
                        "agentstudio.bridge.result": "success",
                        "agentstudio.bridge.result_reason": "none",
                    ]
                )
            ),
        ]

        for sample in acceptedBatches {
            #expect(validator.validate(sample) == .accepted)
        }
    }

    @Test
    func validatorRejectsLegacyReviewPackageBodyTelemetry() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let rejectedBatches = [
            sampleWithWebAttributes(
                WebSampleProps(
                    name: "performance.bridge.web.review_package_first_chunk",
                    phase: "review_package_first_chunk",
                    plane: "data",
                    priority: "hot",
                    slice: "review_metadata",
                    transport: "content",
                    extraStrings: ["agentstudio.bridge.result": "success"],
                    extraNumbers: [
                        "agentstudio.bridge.content.chunk_byte_count": 65_536,
                        "agentstudio.bridge.content.total_bytes_read": 65_536,
                    ]
                )
            ),
            sampleWithWebAttributes(
                WebSampleProps(
                    name: "performance.bridge.web.review_package_body_load",
                    phase: "review_package_body_load",
                    plane: "data",
                    priority: "hot",
                    slice: "review_metadata",
                    transport: "content",
                    extraStrings: ["agentstudio.bridge.result": "success"],
                    extraNumbers: [
                        "agentstudio.bridge.content.byte_count": 1_356_525,
                        "agentstudio.bridge.content.chunk_count": 21,
                    ]
                )
            ),
            sampleWithWebAttributes(
                WebSampleProps(
                    name: "performance.bridge.web.review_package_parse",
                    phase: "review_package_parse",
                    plane: "data",
                    priority: "hot",
                    slice: "review_metadata",
                    transport: "content",
                    extraStrings: ["agentstudio.bridge.result": "success"],
                    extraNumbers: ["agentstudio.bridge.content.byte_count": 1_356_525]
                )
            ),
        ]

        for sample in rejectedBatches {
            #expect(validator.validate(sample) == .dropped(.unsafeEventName))
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

    private func sampleWithWebAttributes(_ props: WebSampleProps) -> BridgeTelemetrySample {
        var stringAttributes = [
            "agentstudio.bridge.phase": props.phase,
            "agentstudio.bridge.plane": props.plane,
            "agentstudio.bridge.priority": props.priority,
            "agentstudio.bridge.slice": props.slice,
            "agentstudio.bridge.transport": props.transport,
        ]
        stringAttributes.merge(props.extraStrings) { _, new in new }
        return BridgeTelemetrySample(
            scope: .web,
            name: props.name,
            durationMilliseconds: 1.25,
            traceContext: nil,
            stringAttributes: stringAttributes,
            numericAttributes: props.extraNumbers,
            booleanAttributes: [:]
        )
    }
}
