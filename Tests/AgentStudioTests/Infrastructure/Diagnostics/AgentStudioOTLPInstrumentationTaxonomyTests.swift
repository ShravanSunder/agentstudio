import Foundation
import Testing

@testable import AgentStudioInfrastructure

@Suite
struct AgentStudioOTLPInstrumentationTaxonomyTests {
    @Test
    func repoExplorerInstrumentDimensionsAreAllowlistedAndBounded() {
        let projection = AgentStudioOTLPTraceProjection.project(
            AgentStudioTraceRecord(
                timeUnixNano: 1,
                severityText: .info,
                body: "performance.repo_explorer.row_body_evaluation",
                traceID: nil,
                spanID: nil,
                parentSpanID: nil,
                resource: ["service.name": "AgentStudio"],
                scope: .init(name: "agentstudio.performance", version: "0.1.0"),
                attributes: [
                    "agentstudio.trace.tag": .string("performance"),
                    "agentstudio.performance.repo_explorer.row_body_evaluation.outcome": .string("success"),
                    "agentstudio.performance.repo_explorer.row_kind": .string("resolved_worktree"),
                    "agentstudio.performance.repo_explorer.surface": .string("repo"),
                    "agentstudio.performance.repo_explorer.scroll_active": .bool(true),
                    "agentstudio.performance.repo_explorer.visible_row_count_bucket": .string("9_16"),
                    "agentstudio.performance.repo_explorer.private_row_id": .string("secret"),
                ]
            )
        )

        #expect(projection.attributes["agentstudio.performance.repo_explorer.row_kind"] == .string("resolved_worktree"))
        #expect(projection.attributes["agentstudio.performance.repo_explorer.scroll_active"] == .bool(true))
        #expect(projection.attributes["agentstudio.performance.repo_explorer.private_row_id"] == nil)
    }

    @Test
    func repoExplorerKeyedWakeRejectsUnknownTaxonomyValues() {
        let projection = AgentStudioOTLPTraceProjection.project(
            AgentStudioTraceRecord(
                timeUnixNano: 2,
                severityText: .info,
                body: "performance.repo_explorer.keyed_wake",
                traceID: nil,
                spanID: nil,
                parentSpanID: nil,
                resource: ["service.name": "AgentStudio"],
                scope: .init(name: "agentstudio.performance", version: "0.1.0"),
                attributes: [
                    "agentstudio.trace.tag": .string("performance"),
                    "agentstudio.performance.repo_explorer.stage": .string("private_stage"),
                    "agentstudio.performance.repo_explorer.key_class": .string("private_key"),
                    "agentstudio.performance.repo_explorer.outcome": .string("private_outcome"),
                ]
            )
        )

        #expect(projection.attributes["agentstudio.performance.repo_explorer.stage"] == nil)
        #expect(projection.attributes["agentstudio.performance.repo_explorer.key_class"] == nil)
        #expect(projection.attributes["agentstudio.performance.repo_explorer.outcome"] == nil)
    }

    @Test
    func stageOutcomeTaxonomiesRejectUnknownValues() {
        let projection = AgentStudioOTLPTraceProjection.project(
            AgentStudioTraceRecord(
                timeUnixNano: 3,
                severityText: .info,
                body: "performance.filesystem.stage_outcome",
                traceID: nil,
                spanID: nil,
                parentSpanID: nil,
                resource: ["service.name": "AgentStudio"],
                scope: .init(name: "agentstudio.performance", version: "0.1.0"),
                attributes: [
                    "agentstudio.trace.tag": .string("performance"),
                    "agentstudio.performance.filesystem.stage": .string("private_stage"),
                    "agentstudio.performance.filesystem.outcome": .string("private_outcome"),
                ]
            )
        )

        #expect(projection.attributes["agentstudio.performance.filesystem.stage"] == nil)
        #expect(projection.attributes["agentstudio.performance.filesystem.outcome"] == nil)
    }
}
