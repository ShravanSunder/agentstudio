import AgentStudioInfrastructure
import Testing

@testable import AgentStudioBridge

@Suite("Bridge annotation catalog telemetry validation")
struct BridgeAnnotationCatalogTelemetryValidatorTests {
    @Test(
        "accepts the exact Main catalog event including its source monotonic timestamp",
        arguments: ["begin", "window", "commit"]
    )
    func acceptsMainCatalogTimestamp(stage: String) {
        // Arrange — the shape produced by recordWorktreeAnnotationLifecycleTelemetry.
        var numbers: [String: Double] = [
            "agentstudio.bridge.annotation.catalog.entry.count": 3,
            "agentstudio.bridge.annotation.catalog.revision": 1,
            "agentstudio.bridge.annotation.catalog.unit.byte_count": 500,
            "agentstudio.bridge.presentation.revision.after": 1,
            "agentstudio.bridge.presentation.revision.before": 0,
            "agentstudio.bridge.source.monotonic_ms": 123.5,
            "agentstudio.bridge.stage.attempt": 0,
        ]
        if stage == "window" {
            numbers["agentstudio.bridge.annotation.catalog.window.ordinal"] = 0
        } else if stage == "commit" {
            numbers["agentstudio.bridge.annotation.catalog.window.count"] = 1
        }
        let sample = BridgeTelemetrySample(
            scope: .web,
            name: "performance.bridge.web.annotation_lifecycle",
            durationMilliseconds: nil,
            traceContext: nil,
            stringAttributes: [
                "agentstudio.bridge.operation.id": String(repeating: "a", count: 64),
                "agentstudio.bridge.phase": "annotation_catalog_main_\(stage)",
                "agentstudio.bridge.plane": "data",
                "agentstudio.bridge.priority": "hot",
                "agentstudio.bridge.result": "success",
                "agentstudio.bridge.slice": "review_projection",
                "agentstudio.bridge.transport": "local",
                "agentstudio.bridge.viewer": "review",
            ],
            numericAttributes: numbers,
            booleanAttributes: [:]
        )
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )

        // Act / Assert — timing metadata is part of the existing closed sender contract.
        #expect(validator.validate(sample) == .accepted)
    }
}
