import Foundation
import Testing

@testable import AgentStudio

@Suite
struct BridgeTelemetryEventValidatorWorkerPaintTests {
    @Test
    func validatorAcceptsWorkerPreparedReviewPaintEmitterShapes() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let materializeSample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.web.code_view_item_materialize",
                phase: "code_view_item_materialize",
                plane: "data",
                priority: "hot",
                slice: "code_view_item",
                transport: "worker",
                extraStrings: [
                    "agentstudio.bridge.content_bytes_bucket": "small",
                    "agentstudio.bridge.item_count_bucket": "small",
                    "agentstudio.bridge.language_class": "typescript",
                    "agentstudio.bridge.result": "success",
                    "agentstudio.bridge.viewer": "review",
                ],
                extraBooleans: [
                    "agentstudio.bridge.selected": true
                ]
            )
        )
        let paintedSample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.web.selected_content_painted",
                phase: "selected_content_painted",
                plane: "data",
                priority: "hot",
                slice: "code_view_item",
                transport: "worker",
                extraStrings: [
                    "agentstudio.bridge.viewer": "review"
                ],
                extraNumbers: [
                    "agentstudio.bridge.selected_content.click_to_paint_ms": 32,
                    "agentstudio.bridge.selected_content.frame_wait_ms": 8,
                    "agentstudio.bridge.selected_content.materialize_ms": 12,
                ]
            )
        )

        #expect(validator.validate(materializeSample) == .accepted)
        #expect(validator.validate(paintedSample) == .accepted)
    }
}
