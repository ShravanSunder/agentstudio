import Testing

@testable import AgentStudio

@Suite
struct AgentStudioOTLPBridgeSidebarMetricTests {
    @Test
    func bridgePerformanceRecordProjectsOnlySafeBridgeMetrics() throws {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 124,
            severityText: .info,
            body: "performance.bridge.webkit.push_envelope",
            traceID: "11111111111111111111111111111111",
            spanID: "2222222222222222",
            parentSpanID: "3333333333333333",
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.bridge.performance.webkit", version: "0.1.0"),
            attributes: [
                "agentstudio.bridge.content.byte_size_bucket": .int(100_000),
                "agentstudio.bridge.content.line_count_bucket": .int(500),
                "agentstudio.bridge.item_id": .string("private-item-id"),
                "agentstudio.bridge.phase": .string("transport"),
                "agentstudio.bridge.plane": .string("data"),
                "agentstudio.bridge.priority": .string("cold"),
                "agentstudio.bridge.slice": .string("review_metadata"),
                "agentstudio.performance.elapsed_ms": .double(8.5),
                "agentstudio.trace.tag": .string("bridge.performance.webkit"),
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))
        let expectedDimensions = [
            AgentStudioOTLPPerformanceMetricDimension(
                name: "event",
                value: "performance.bridge.webkit.push_envelope"
            ),
            AgentStudioOTLPPerformanceMetricDimension(name: "phase", value: "transport"),
            AgentStudioOTLPPerformanceMetricDimension(name: "plane", value: "data"),
            AgentStudioOTLPPerformanceMetricDimension(name: "priority", value: "cold"),
            AgentStudioOTLPPerformanceMetricDimension(name: "slice", value: "review_metadata"),
        ]

        #expect(metricEvent.eventName == "performance.bridge.webkit.push_envelope")
        #expect(metricEvent.elapsedMilliseconds == 8.5)
        #expect(metricEvent.dimensions == expectedDimensions)
        #expect(
            metricEvent.samples == [
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.bridge.webkit.push_envelope",
                    label: "agentstudio_bridge_content_byte_size_bucket",
                    dimensions: expectedDimensions,
                    value: 100_000
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.bridge.webkit.push_envelope",
                    label: "agentstudio_bridge_content_line_count_bucket",
                    dimensions: expectedDimensions,
                    value: 500
                ),
            ])
    }

    @Test
    func bridgeDemandQueueWaitProjectsLaneDimensionAndSchedulerGauges() throws {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 125,
            severityText: .info,
            body: "performance.bridge.swift.metadata_scheduler_queue_wait",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.bridge.performance.swift", version: "0.1.0"),
            attributes: [
                "agent.proof.marker": .string("bridge-headless-manifest-proof"),
                "agentstudio.bridge.demand.lane": .string("foreground"),
                "agentstudio.bridge.demand.queue_depth": .double(7),
                "agentstudio.bridge.demand.scheduler_queue_wait_ms": .double(12.5),
                "agentstudio.bridge.phase": .string("demand_queue_wait"),
                "agentstudio.bridge.plane": .string("data"),
                "agentstudio.bridge.priority": .string("hot"),
                "agentstudio.bridge.slice": .string("tree_prepare_input"),
                "agentstudio.performance.elapsed_ms": .double(12.5),
                "agentstudio.trace.tag": .string("bridge.performance.swift"),
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))
        let expectedDimensions = [
            AgentStudioOTLPPerformanceMetricDimension(
                name: "event",
                value: "performance.bridge.swift.metadata_scheduler_queue_wait"
            ),
            AgentStudioOTLPPerformanceMetricDimension(
                name: "agent.proof.marker",
                value: "bridge-headless-manifest-proof"
            ),
            AgentStudioOTLPPerformanceMetricDimension(name: "phase", value: "demand_queue_wait"),
            AgentStudioOTLPPerformanceMetricDimension(name: "plane", value: "data"),
            AgentStudioOTLPPerformanceMetricDimension(name: "priority", value: "hot"),
            AgentStudioOTLPPerformanceMetricDimension(name: "slice", value: "tree_prepare_input"),
            AgentStudioOTLPPerformanceMetricDimension(name: "lane", value: "foreground"),
        ]

        #expect(metricEvent.dimensions == expectedDimensions)
        #expect(metricEvent.elapsedMilliseconds == 12.5)
        #expect(
            metricEvent.samples == [
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.bridge.swift.metadata_scheduler_queue_wait",
                    label: "agentstudio_bridge_demand_queue_depth",
                    dimensions: expectedDimensions,
                    value: 7
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.bridge.swift.metadata_scheduler_queue_wait",
                    label: "agentstudio_bridge_demand_scheduler_queue_wait_ms",
                    dimensions: expectedDimensions,
                    value: 12.5
                ),
            ])
    }

    @Test
    func bridgeTimeToFirstInteractionProjectsVariantDimension() throws {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 126,
            severityText: .info,
            body: "performance.bridge.viewer.time_to_first_interaction",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.bridge.performance.web", version: "0.1.0"),
            attributes: [
                "agentstudio.bridge.phase": .string("time_to_first_interaction"),
                "agentstudio.bridge.plane": .string("data"),
                "agentstudio.bridge.priority": .string("hot"),
                "agentstudio.bridge.slice": .string("content_fetch"),
                "agentstudio.bridge.viewer": .string("file"),
                "agentstudio.bridge.viewer.ttfi_variant": .string("cold"),
                "agentstudio.performance.elapsed_ms": .double(1429),
                "agentstudio.trace.tag": .string("bridge.performance.web"),
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))
        let expectedDimensions = [
            AgentStudioOTLPPerformanceMetricDimension(
                name: "event",
                value: "performance.bridge.viewer.time_to_first_interaction"
            ),
            AgentStudioOTLPPerformanceMetricDimension(name: "phase", value: "time_to_first_interaction"),
            AgentStudioOTLPPerformanceMetricDimension(name: "plane", value: "data"),
            AgentStudioOTLPPerformanceMetricDimension(name: "priority", value: "hot"),
            AgentStudioOTLPPerformanceMetricDimension(name: "slice", value: "content_fetch"),
            AgentStudioOTLPPerformanceMetricDimension(name: "variant", value: "cold"),
        ]

        #expect(metricEvent.dimensions == expectedDimensions)
        #expect(metricEvent.elapsedMilliseconds == 1429)
    }

    @Test
    func bridgePerformanceRecordRequiresCompleteFiniteTaxonomy() {
        let missingPhase = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 124,
            severityText: .info,
            body: "performance.bridge.webkit.push_envelope",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.bridge.performance.webkit", version: "0.1.0"),
            attributes: [
                "agentstudio.bridge.plane": .string("data"),
                "agentstudio.bridge.priority": .string("cold"),
                "agentstudio.bridge.slice": .string("review_metadata"),
            ]
        )
        let invalidSlice = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 125,
            severityText: .info,
            body: "performance.bridge.webkit.push_envelope",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.bridge.performance.webkit", version: "0.1.0"),
            attributes: [
                "agentstudio.bridge.phase": .string("transport"),
                "agentstudio.bridge.plane": .string("data"),
                "agentstudio.bridge.priority": .string("cold"),
                "agentstudio.bridge.slice": .string("not_a_slice"),
            ]
        )

        #expect(AgentStudioOTLPPerformanceMetricEvent(record: missingPhase) == nil)
        #expect(AgentStudioOTLPPerformanceMetricEvent(record: invalidSlice) == nil)
    }

    @Test
    func sidebarPerformanceRecordProjectsControlledTaxonomyDimensions() throws {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 130,
            severityText: .info,
            body: "performance.sidebar.projection",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.elapsed_ms": .double(4.5),
                "agentstudio.performance.sidebar.surface": .string("inbox"),
                "agentstudio.performance.sidebar.phase": .string("mainactor_apply"),
                "agentstudio.performance.sidebar.query_state": .string("non_empty"),
                "agentstudio.performance.sidebar.group_mode": .string("none"),
                "agentstudio.performance.sidebar.trigger": .string("grouping_switch"),
                "agentstudio.performance.sidebar.input.count": .int(42),
                "agentstudio.performance.sidebar.group.count": .int(4),
                "agentstudio.performance.sidebar.mainactor_apply_elapsed_ms": .double(4.5),
                "agentstudio.performance.sidebar.query_character.count": .int(3),
                "agentstudio.performance.sidebar.request_build_mainactor_elapsed_ms": .double(0.5),
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))
        let expectedDimensions = [
            AgentStudioOTLPPerformanceMetricDimension(name: "event", value: "performance.sidebar.projection"),
            AgentStudioOTLPPerformanceMetricDimension(name: "surface", value: "inbox"),
            AgentStudioOTLPPerformanceMetricDimension(name: "phase", value: "mainactor_apply"),
            AgentStudioOTLPPerformanceMetricDimension(name: "query_state", value: "non_empty"),
            AgentStudioOTLPPerformanceMetricDimension(name: "group_mode", value: "none"),
            AgentStudioOTLPPerformanceMetricDimension(name: "trigger", value: "grouping_switch"),
        ]

        #expect(metricEvent.dimensions == expectedDimensions)
        #expect(metricEvent.elapsedMilliseconds == 4.5)
        #expect(
            metricEvent.samples == [
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.sidebar.projection",
                    label: "agentstudio_performance_sidebar_group_count",
                    dimensions: expectedDimensions,
                    value: 4
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.sidebar.projection",
                    label: "agentstudio_performance_sidebar_input_count",
                    dimensions: expectedDimensions,
                    value: 42
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.sidebar.projection",
                    label: "agentstudio_performance_sidebar_mainactor_apply_elapsed_ms",
                    dimensions: expectedDimensions,
                    value: 4.5
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.sidebar.projection",
                    label: "agentstudio_performance_sidebar_query_character_count",
                    dimensions: expectedDimensions,
                    value: 3
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.sidebar.projection",
                    label: "agentstudio_performance_sidebar_request_build_mainactor_elapsed_ms",
                    dimensions: expectedDimensions,
                    value: 0.5
                ),
            ])
    }

    @Test
    func sidebarPerformanceRecordRejectsMissingSurfaceTaxonomy() {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 130,
            severityText: .info,
            body: "performance.sidebar.projection",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.elapsed_ms": .double(4.5),
                "agentstudio.performance.sidebar.phase": .string("mainactor_apply"),
                "agentstudio.performance.sidebar.query_state": .string("non_empty"),
                "agentstudio.performance.sidebar.group_mode": .string("none"),
                "agentstudio.performance.sidebar.trigger": .string("grouping_switch"),
            ]
        )

        #expect(AgentStudioOTLPPerformanceMetricEvent(record: record) == nil)
    }

    @Test
    func sidebarPerformanceRecordAcceptsVisibilityModeTrigger() throws {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 131,
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
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))

        #expect(
            metricEvent.dimensions.contains(
                AgentStudioOTLPPerformanceMetricDimension(name: "trigger", value: "visibility_mode")))
        #expect(
            metricEvent.samples.contains(
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.sidebar.projection",
                    label: "agentstudio_performance_sidebar_total_worker_elapsed_ms",
                    dimensions: metricEvent.dimensions,
                    value: 1.5
                )))
    }

    @Test
    func sidebarPerformanceRecordAcceptsSortOrderTrigger() throws {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 132,
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
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))

        #expect(
            metricEvent.dimensions.contains(
                AgentStudioOTLPPerformanceMetricDimension(name: "trigger", value: "sort_order")))
        #expect(
            metricEvent.samples.contains(
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.sidebar.projection",
                    label: "agentstudio_performance_sidebar_total_worker_elapsed_ms",
                    dimensions: metricEvent.dimensions,
                    value: 2.25
                )))
    }

    @Test
    func sidebarPerformanceRecordRequiresCompleteControlledTaxonomy() {
        let missingSurface = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 132,
            severityText: .info,
            body: "performance.sidebar.projection",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.sidebar.phase": .string("mainactor_apply"),
                "agentstudio.performance.sidebar.query_state": .string("empty"),
                "agentstudio.performance.sidebar.group_mode": .string("not_applicable"),
            ]
        )
        let invalidPhase = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 133,
            severityText: .info,
            body: "performance.sidebar.projection",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.sidebar.surface": .string("inbox"),
                "agentstudio.performance.sidebar.phase": .string("query_text_/Users/private"),
                "agentstudio.performance.sidebar.query_state": .string("empty"),
                "agentstudio.performance.sidebar.group_mode": .string("not_applicable"),
                "agentstudio.performance.sidebar.trigger": .string("startup_diagnostic"),
            ]
        )

        #expect(AgentStudioOTLPPerformanceMetricEvent(record: missingSurface) == nil)
        #expect(AgentStudioOTLPPerformanceMetricEvent(record: invalidPhase) == nil)
    }

}
