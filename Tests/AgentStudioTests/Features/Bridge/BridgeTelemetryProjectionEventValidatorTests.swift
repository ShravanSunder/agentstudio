import Foundation
import Testing

@testable import AgentStudioBridge

@Suite
struct BridgeTelemetryProjectionEventValidatorTests {
    @Test
    func validatorAcceptsProjectionCoordinatorEventsFlushedByBrowser() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let samples = [
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

        for sample in samples {
            #expect(validator.validate(sample) == .accepted)
        }
    }

    @Test
    func validatorAcceptsOnlyScrubbedAnnotationLifecycleCorrelation() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let sample = annotationLifecycleSample(operationCorrelationID: String(repeating: "a", count: 64))

        #expect(validator.validate(sample) == .accepted)
        #expect(
            validator.validate(
                annotationLifecycleSample(operationCorrelationID: "raw-operation-uuid")
            ) == .dropped(.unsafeAttribute)
        )
    }
}

private func annotationLifecycleSample(operationCorrelationID: String) -> BridgeTelemetrySample {
    BridgeTelemetrySample(
        scope: .web,
        name: "performance.bridge.web.annotation_lifecycle",
        durationMilliseconds: nil,
        traceContext: nil,
        stringAttributes: [
            "agentstudio.bridge.operation.id": operationCorrelationID,
            "agentstudio.bridge.phase": "main_thread_install_terminal",
            "agentstudio.bridge.plane": "data",
            "agentstudio.bridge.priority": "hot",
            "agentstudio.bridge.result": "success",
            "agentstudio.bridge.slice": "review_projection",
            "agentstudio.bridge.transport": "local",
            "agentstudio.bridge.viewer": "review",
        ],
        numericAttributes: [
            "agentstudio.bridge.source.generation": 7,
            "agentstudio.bridge.stage.attempt": 0,
        ],
        booleanAttributes: [:]
    )
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
