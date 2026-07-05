import Testing

@testable import AgentStudio

@Suite
struct BridgeTelemetryPackageReasonTests {
    @Test
    func validatorRejectsNativePackageBuildReasonFromBrowserIngress() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.swift])
        )
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_build_reason_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .swift,
                    name: "performance.bridge.swift.package_build",
                    durationMilliseconds: nil,
                    traceContext: nil,
                    stringAttributes: [
                        "agentstudio.bridge.package_build.reason": "initial_intake",
                        "agentstudio.bridge.phase": "package_build",
                        "agentstudio.bridge.plane": "data",
                        "agentstudio.bridge.priority": "cold",
                        "agentstudio.bridge.slice": "review_metadata",
                        "agentstudio.bridge.transport": "swift",
                    ],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )

        #expect(validator.validate(batch) == .dropped(.disabledScope))
    }
}
