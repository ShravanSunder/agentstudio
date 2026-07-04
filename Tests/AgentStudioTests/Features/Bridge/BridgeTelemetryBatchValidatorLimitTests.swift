import Foundation
import Testing

@testable import AgentStudio

@Suite
struct BridgeTelemetryBatchValidatorLimitTests {
    @Test
    func validatorRejectsTooManySamples() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let samples = Array(
            repeating: BridgeTelemetrySample(
                scope: .web,
                name: "performance.bridge.web.push_apply",
                durationMilliseconds: nil,
                traceContext: nil,
                stringAttributes: [:],
                numericAttributes: [:],
                booleanAttributes: [:]
            ),
            count: BridgeTelemetryLimits.maxSamplesPerBatch + 1
        )
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: samples
        )

        #expect(validator.validate(batch) == .dropped(.tooManySamples))
    }
}
