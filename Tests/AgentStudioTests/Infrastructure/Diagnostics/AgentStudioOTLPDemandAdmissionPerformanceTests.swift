import Testing

@testable import AgentStudioInfrastructure

@Suite
struct AgentStudioOTLPDemandAdmissionPerformanceTests {
    @Test
    func repoExplorerStageSnapshotProjectsOnlyBoundedDimensionsAndIntervalCounter() throws {
        let validRecord = AgentStudioTraceRecord(
            timeUnixNano: 127,
            severityText: .info,
            body: "performance.repo_explorer.stage_snapshot",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.repo_explorer.stage": .string("projection_worker"),
                "agentstudio.performance.repo_explorer.outcome": .string("published"),
                "agentstudio.performance.repo_explorer.interval.count": .int(17),
            ]
        )

        let validProjection = AgentStudioOTLPTraceProjection.project(validRecord)
        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: validProjection))

        #expect(metricEvent.dimensionTuples.contains { $0 == ("stage", "projection_worker") })
        #expect(metricEvent.dimensionTuples.contains { $0 == ("outcome", "published") })
        #expect(
            metricEvent.measurements.contains {
                guard case .counter(let sample) = $0 else { return false }
                return sample.label == "agentstudio_performance_repo_explorer_interval_count"
                    && sample.value == 17
            }
        )

        let invalidRecord = AgentStudioTraceRecord(
            timeUnixNano: 128,
            severityText: .info,
            body: "performance.repo_explorer.stage_snapshot",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.repo_explorer.stage": .string("private-unbounded-stage"),
                "agentstudio.performance.repo_explorer.outcome": .string("private-unbounded-outcome"),
                "agentstudio.performance.repo_explorer.interval.count": .int(1),
            ]
        )

        let invalidProjection = AgentStudioOTLPTraceProjection.project(invalidRecord)
        #expect(invalidProjection.attributes["agentstudio.performance.repo_explorer.stage"] == nil)
        #expect(invalidProjection.attributes["agentstudio.performance.repo_explorer.outcome"] == nil)
    }

    @Test
    func forgeAggregateProjectsEveryDeclaredNumericAttributeAsCounter() throws {
        let expectedCounterKeys = [
            "agentstudio.performance.forge.input.automatic.count",
            "agentstudio.performance.forge.input.manual.count",
            "agentstudio.performance.forge.input.follow_up.count",
            "agentstudio.performance.forge.admission.admitted.count",
            "agentstudio.performance.forge.admission.no_demand_rejected.count",
            "agentstudio.performance.forge.admission.missing_origin_rejected.count",
            "agentstudio.performance.forge.admission.active_request_coalesced.count",
            "agentstudio.performance.forge.admission.capacity_limited.count",
            "agentstudio.performance.forge.admission.freshness_deferred.count",
            "agentstudio.performance.forge.admission.backoff_deferred.count",
            "agentstudio.performance.forge.execution.started.count",
            "agentstudio.performance.forge.execution.completed.count",
            "agentstudio.performance.forge.execution.failed.count",
            "agentstudio.performance.forge.execution.cancelled.count",
            "agentstudio.performance.forge.execution.superseded.count",
            "agentstudio.performance.forge.validation.current.count",
            "agentstudio.performance.forge.validation.stale_generation.count",
            "agentstudio.performance.forge.validation.stale_origin.count",
            "agentstudio.performance.forge.validation.stale_scope.count",
            "agentstudio.performance.forge.publication.published.count",
            "agentstudio.performance.forge.publication.equal.count",
            "agentstudio.performance.forge.publication.invalidated.count",
            "agentstudio.performance.forge.deadline.scheduled.count",
            "agentstudio.performance.forge.deadline.rescheduled.count",
            "agentstudio.performance.forge.deadline.fired.count",
            "agentstudio.performance.forge.deadline.cancelled.count",
        ]
        var attributes: [String: AgentStudioTraceValue] = [:]
        for (index, key) in expectedCounterKeys.enumerated() {
            attributes[key] = .int(index + 1)
        }
        attributes["agentstudio.performance.forge.private_unbounded.count"] = .int(999)
        let record = AgentStudioTraceRecord(
            timeUnixNano: 129,
            severityText: .info,
            body: "performance.forge.refresh",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: attributes
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)
        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: projection))

        #expect(expectedCounterKeys.allSatisfy { projection.attributes[$0] != nil })
        #expect(projection.attributes["agentstudio.performance.forge.private_unbounded.count"] == nil)
        #expect(metricEvent.measurements.count == expectedCounterKeys.count)
        #expect(
            metricEvent.measurements.allSatisfy {
                guard case .counter = $0 else { return false }
                return true
            }
        )
    }
}
