import AgentStudioInfrastructure
import Testing

@testable import AgentStudioBridge

@Suite("Bridge Review refresh telemetry validation")
struct BridgeReviewRefreshTelemetryValidatorTests {
    @Test(
        "accepts the existing worker candidate-failure sample and rejects unknown reasons",
        arguments: ["retryable", "not_retryable"]
    )
    func acceptsWorkerCandidateFailure(resultReason: String) {
        // Arrange — exact event shape emitted by recordBridgeReviewRefreshLifecycleTelemetry.
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let candidateFailure = sample(
            phase: "review_refresh_candidate_failed",
            resultReason: resultReason,
            extraStrings: [
                "agentstudio.bridge.result": "failure",
                "agentstudio.bridge.review.refresh.presentation_class": "ordinary",
                "agentstudio.bridge.review.refresh.promotion_reason": "none",
            ],
            numbers: [
                "agentstudio.bridge.review.generation": 1,
                "agentstudio.bridge.review.refresh.affected_stable_file.count": 0,
            ]
        )

        // Act / Assert — failure is a required observation, not an invalid wire sample.
        #expect(validator.validate(candidateFailure) == .accepted)
        let unknownReason = sample(
            phase: "review_refresh_candidate_failed",
            resultReason: "unclassified_retry_policy",
            extraStrings: candidateFailure.stringAttributes.filter {
                $0.key != "agentstudio.bridge.result_reason"
            },
            numbers: candidateFailure.numericAttributes
        )
        #expect(validator.validate(unknownReason) == .dropped(.unsafeAttribute))
    }

    @Test("accepts only the controlled web lifecycle shapes")
    func acceptsControlledWebLifecycleShapes() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let installTerminal = sample(
            phase: "review_refresh_install_terminal",
            resultReason: "none",
            extraStrings: [
                "agentstudio.bridge.review.refresh.install_trigger": "apply_now",
                "agentstudio.bridge.review.refresh.presentation_class": "promoted",
                "agentstudio.bridge.review.refresh.promotion_reason": "files",
            ],
            numbers: [
                "agentstudio.bridge.review.generation": 7,
                "agentstudio.bridge.review.refresh.affected_stable_file.count": 3,
            ]
        )
        let cleanup = sample(
            phase: "review_refresh_cleanup_terminal",
            resultReason: "worker_replacement",
            extraStrings: [:],
            numbers: [
                "agentstudio.bridge.review.refresh.active_bank.count": 0,
                "agentstudio.bridge.review.refresh.candidate_bank.count": 0,
            ]
        )

        #expect(validator.validate(installTerminal) == .accepted)
        #expect(validator.validate(cleanup) == .accepted)
    }

    private func sample(
        phase: String,
        resultReason: String,
        extraStrings: [String: String],
        numbers: [String: Double]
    ) -> BridgeTelemetrySample {
        BridgeTelemetrySample(
            scope: .web,
            name: "performance.bridge.web.review_refresh_lifecycle",
            durationMilliseconds: nil,
            traceContext: nil,
            stringAttributes: [
                "agentstudio.bridge.phase": phase,
                "agentstudio.bridge.plane": "control",
                "agentstudio.bridge.priority": "hot",
                "agentstudio.bridge.result": "success",
                "agentstudio.bridge.result_reason": resultReason,
                "agentstudio.bridge.slice": "review_metadata",
                "agentstudio.bridge.transport": "worker",
            ].merging(extraStrings) { _, incoming in incoming },
            numericAttributes: numbers,
            booleanAttributes: [:]
        )
    }
}
