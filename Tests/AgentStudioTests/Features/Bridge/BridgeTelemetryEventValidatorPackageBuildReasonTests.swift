import Testing

@testable import AgentStudio

@Suite
struct BridgeTelemetryPackageReasonTests {
    @Test
    func validatorRejectsNativePackageBuildReasonFromBrowserIngress() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.swift])
        )
        let sample = BridgeTelemetrySample(
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

        #expect(validator.validate(sample) == .dropped(.disabledScope))
    }
}
