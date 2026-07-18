import Testing

@testable import AgentStudio

@Suite
struct AgentStudioRuntimePressureOTLPProjectionTests {
    @Test
    func aggregateProjectionKeepsOnlyBoundedNumericVocabulary() {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 602,
            severityText: .info,
            body: "performance.terminal.accumulator_drain",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.elapsed_ms": .double(3.5),
                "agentstudio.performance.terminal.accumulator.offered.count": .int(100),
                "agentstudio.performance.terminal.accumulator.replaced.count": .int(80),
                "agentstudio.performance.terminal.accumulator.retained_entry.count": .int(4),
                "agentstudio.performance.terminal.accumulator.retained_size_bytes": .int(256),
                "agentstudio.performance.terminal.accumulator.pane_id": .string("private-pane"),
                "agentstudio.performance.terminal.accumulator.path": .string("/private/path"),
                "agentstudio.performance.terminal.accumulator.payload": .string("terminal output"),
                "agentstudio.performance.terminal.accumulator.error": .string("private error"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)
        let renderedProjection = projection.renderedForCanaryAssertions()

        #expect(projection.attributes["agentstudio.performance.elapsed_ms"] == .double(3.5))
        #expect(
            projection.attributes["agentstudio.performance.terminal.accumulator.offered.count"]
                == .int(100))
        #expect(
            projection.attributes["agentstudio.performance.terminal.accumulator.replaced.count"]
                == .int(80))
        #expect(
            projection.attributes["agentstudio.performance.terminal.accumulator.retained_entry.count"]
                == .int(4))
        #expect(
            projection.attributes["agentstudio.performance.terminal.accumulator.retained_size_bytes"]
                == .int(256))
        #expect(!renderedProjection.contains("private-pane"))
        #expect(!renderedProjection.contains("/private/path"))
        #expect(!renderedProjection.contains("terminal output"))
        #expect(!renderedProjection.contains("private error"))
    }
}
