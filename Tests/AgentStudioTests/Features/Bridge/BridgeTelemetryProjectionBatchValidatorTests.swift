import Foundation
import Testing

@testable import AgentStudio

@Suite
struct BridgeTelemetryProjectionBatchValidatorTests {
    @Test
    func validatorAcceptsProjectionCoordinatorBatchFlushedByBrowser() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                projectionCoordinatorSample(
                    name: "performance.bridge.web.projection_input_build",
                    phase: "projection_input_build"
                ),
                projectionCoordinatorSample(
                    name: "performance.bridge.web.projection_store_apply",
                    phase: "projection_store_apply"
                ),
                projectionCoordinatorSample(
                    name: "performance.bridge.web.projection_total",
                    phase: "projection_total"
                ),
                projectionBuildSample(),
            ]
        )

        #expect(validator.validate(batch) == .accepted(batch))
    }
}

private func projectionCoordinatorSample(name: String, phase: String) -> BridgeTelemetrySample {
    BridgeTelemetrySample(
        scope: .web,
        name: name,
        durationMilliseconds: 1,
        traceContext: nil,
        stringAttributes: [
            "agentstudio.bridge.phase": phase,
            "agentstudio.bridge.plane": "data",
            "agentstudio.bridge.priority": "warm",
            "agentstudio.bridge.result": "success",
            "agentstudio.bridge.slice": "review_projection",
            "agentstudio.bridge.transport": "worker",
            "agentstudio.bridge.worker.lane": "projection",
        ],
        numericAttributes: ["agentstudio.bridge.review.item_count": 12],
        booleanAttributes: [:]
    )
}

private func projectionBuildSample() -> BridgeTelemetrySample {
    BridgeTelemetrySample(
        scope: .web,
        name: "performance.bridge.trees.projection_build",
        durationMilliseconds: 1,
        traceContext: nil,
        stringAttributes: [
            "agentstudio.bridge.fixture_class": "smoke",
            "agentstudio.bridge.item_count_bucket": "small",
            "agentstudio.bridge.phase": "projection_build",
            "agentstudio.bridge.plane": "data",
            "agentstudio.bridge.priority": "warm",
            "agentstudio.bridge.projection.kind": "normal_review",
            "agentstudio.bridge.result": "success",
            "agentstudio.bridge.slice": "review_projection",
            "agentstudio.bridge.transport": "worker",
            "agentstudio.bridge.tree_path_count_bucket": "small",
            "agentstudio.bridge.worker.lane": "projection",
        ],
        numericAttributes: [:],
        booleanAttributes: [:]
    )
}
