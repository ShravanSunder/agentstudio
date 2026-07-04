import Testing

@testable import AgentStudio

struct AgentStudioOTLPSidebarTraceProjectionTests {
    @Test
    func sidebarVisibilityProjectionKeepsControlledTrigger() {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 178,
            severityText: .info,
            body: "performance.sidebar.projection",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.elapsed_ms": .double(1.5),
                "agentstudio.performance.sidebar.surface": .string("repo"),
                "agentstudio.performance.sidebar.phase": .string("projection_worker"),
                "agentstudio.performance.sidebar.query_state": .string("empty"),
                "agentstudio.performance.sidebar.group_mode": .string("repo"),
                "agentstudio.performance.sidebar.trigger": .string("visibility_mode"),
                "agentstudio.performance.sidebar.total_worker_elapsed_ms": .double(1.5),
                "agentstudio.trace.tag": .string("performance"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)

        #expect(projection.attributes["agentstudio.performance.sidebar.trigger"] == .string("visibility_mode"))
        #expect(projection.attributes["agentstudio.performance.sidebar.total_worker_elapsed_ms"] == .double(1.5))
    }

    @Test
    func sidebarSortProjectionKeepsControlledTrigger() {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 179,
            severityText: .info,
            body: "performance.sidebar.projection",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.elapsed_ms": .double(2.25),
                "agentstudio.performance.sidebar.surface": .string("repo"),
                "agentstudio.performance.sidebar.phase": .string("projection_worker"),
                "agentstudio.performance.sidebar.query_state": .string("empty"),
                "agentstudio.performance.sidebar.group_mode": .string("repo"),
                "agentstudio.performance.sidebar.trigger": .string("sort_order"),
                "agentstudio.performance.sidebar.total_worker_elapsed_ms": .double(2.25),
                "agentstudio.trace.tag": .string("performance"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)

        #expect(projection.attributes["agentstudio.performance.sidebar.trigger"] == .string("sort_order"))
        #expect(projection.attributes["agentstudio.performance.sidebar.total_worker_elapsed_ms"] == .double(2.25))
    }
}
