import Foundation
import Testing

@testable import AgentStudio

@Suite
struct AgentStudioOTLPPerformanceTraceProjectionTests {
    @Test
    func performanceProjectionKeepsSafeNumericFieldsAndDropsUnsafeContext() {
        let worktreeID = UUID(uuidString: "6DE2BC87-AD1F-4271-96DD-7922D58612D5")!
        let record = performanceProjectionRecord(worktreeID: worktreeID)

        let projection = AgentStudioOTLPTraceProjection.project(record)
        let renderedProjection = projection.renderedForCanaryAssertions()

        #expect(projection.body == "performance.git.status")
        #expect(projection.attributes["agent.proof.marker"] == .string("perf-proof"))
        #expect(projection.attributes["agentstudio.trace.tag"] == .string("performance"))
        #expect(projection.attributes["agentstudio.performance.git.running.count"] == .int(4))
        #expect(projection.attributes["agentstudio.performance.git.status.duration_ms"] == .double(2.5))
        #expect(projection.attributes["agentstudio.performance.git.status.elapsed_ms"] == .double(2.7))
        #expect(projection.attributes["agentstudio.performance.git.status_unavailable.reason"] == .string("timeout"))
        #expect(projection.attributes["agentstudio.performance.git.root_path"] == nil)
        #expect(projection.attributes["agentstudio.performance.repo.dynamic_key.count"] == nil)
        #expect(projection.attributes["agentstudio.performance.future.elapsed_ms"] == nil)
        #expect(projection.attributes["agentstudio.performance.future.has_value"] == nil)
        #expect(projection.attributes["agentstudio.performance.atom.kind"] == .string("entity_map"))
        #expect(projection.attributes["agentstudio.performance.atom.operation"] == .string("value"))
        #expect(projection.attributes["agentstudio.performance.atom.slot.count"] == .int(2))
        #expect(projection.attributes["agentstudio.performance.atom.cached_key.count"] == .int(1))
        #expect(projection.attributes["agentstudio.performance.atom.cache_hit"] == .bool(false))
        #expect(projection.attributes["agentstudio.performance.coordinator.activity_write.count"] == .int(3))
        #expect(
            projection.attributes["agentstudio.performance.coordinator.filesystem_source_elapsed_ms"]
                == .double(4.5))
        #expect(projection.attributes["agentstudio.performance.coordinator.index_elapsed_ms"] == .double(5.5))
        #expect(
            projection.attributes["agentstudio.performance.coordinator.mainactor_apply_elapsed_ms"]
                == .double(0.5))
        #expect(projection.attributes["agentstudio.performance.coordinator.phase"] == .string("source_sync"))
        #expect(projection.attributes["agentstudio.performance.coordinator.total_elapsed_ms"] == .double(10.5))
        #expect(
            projection.attributes["agentstudio.performance.management_layer.command"]
                == .string("toggleManagementLayer"))
        #expect(projection.attributes["agentstudio.performance.note_text"] == nil)
        #expect(projection.attributes["agentstudio.performance.pane_action.name"] == .string("minimizePane"))
        #expect(projection.attributes["agentstudio.performance.sidebar.is_collapsed"] == .bool(true))
        #expect(projection.attributes["agentstudio.performance.sidebar.split_width"] == .double(1200))
        #expect(projection.attributes["agentstudio.performance.sidebar.toggle.intent"] == .string("collapse"))
        #expect(projection.attributes["agentstudio.performance.sidebar.was_collapsed"] == .bool(false))
        #expect(projection.attributes["agentstudio.performance.sidebar.width"] == .double(320))
        #expect(
            projection.attributes["agentstudio.performance.terminal.geometry.reason"]
                == .string("splitViewDidResizeSubviews"))
        #expect(projection.attributes["agentstudio.performance.terminal.geometry.visible_terminal.count"] == .double(7))
        #expect(projection.attributes["agentstudio.performance.terminal.surface.cell_height_px"] == .double(28))
        #expect(projection.attributes["agentstudio.performance.terminal.surface.cell_width_px"] == .double(14))
        #expect(projection.attributes["agentstudio.performance.terminal.surface.column.count"] == .double(80))
        #expect(projection.attributes["agentstudio.performance.terminal.surface.current_height_px"] == .double(780))
        #expect(projection.attributes["agentstudio.performance.terminal.surface.current_width_px"] == .double(1200))
        #expect(projection.attributes["agentstudio.performance.terminal.surface.dedup_likely"] == .bool(false))
        #expect(projection.attributes["agentstudio.performance.terminal.surface.has_superview"] == .bool(true))
        #expect(projection.attributes["agentstudio.performance.terminal.surface.has_window"] == .bool(true))
        #expect(projection.attributes["agentstudio.performance.terminal.surface.hidden"] == .bool(false))
        #expect(projection.attributes["agentstudio.performance.terminal.surface.requested_height_px"] == .double(800))
        #expect(projection.attributes["agentstudio.performance.terminal.surface.requested_width_px"] == .double(1280))
        #expect(projection.attributes["agentstudio.performance.terminal.surface.row.count"] == .double(24))
        #expect(
            projection.attributes["agentstudio.performance.terminal.surface.source"]
                == .string("forceGeometrySync"))
        #expect(projection.attributes["agentstudio.worktree.id"] == nil)
        #expect(projection.resource["process.pid"] == nil)
        #expect(!renderedProjection.contains("/Users/shravan"))
        #expect(!renderedProjection.contains(worktreeID.uuidString))
    }

    @Test
    func runtimePressureProjectionKeepsMemoryGauges() {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 601,
            severityText: .info,
            body: "performance.process.malloc_zone",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.process.malloc.blocks_in_use": .int(7),
                "agentstudio.performance.process.malloc.size_in_use_bytes": .int(11),
                "agentstudio.performance.process.malloc.maximum_size_in_use_bytes": .int(13),
                "agentstudio.performance.process.malloc.size_allocated_bytes": .int(17),
                "agentstudio.performance.private_payload": .string("do not export"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)

        #expect(projection.attributes["agentstudio.performance.process.malloc.blocks_in_use"] == .int(7))
        #expect(projection.attributes["agentstudio.performance.process.malloc.size_in_use_bytes"] == .int(11))
        #expect(
            projection.attributes["agentstudio.performance.process.malloc.maximum_size_in_use_bytes"] == .int(13))
        #expect(projection.attributes["agentstudio.performance.process.malloc.size_allocated_bytes"] == .int(17))
        #expect(projection.attributes["agentstudio.performance.private_payload"] == nil)
    }

    private func performanceProjectionRecord(worktreeID: UUID) -> AgentStudioTraceRecord {
        AgentStudioTraceRecord(
            timeUnixNano: 600,
            severityText: .info,
            body: "performance.git.status",
            traceID: "trace-should-not-export",
            spanID: "span-should-not-export",
            parentSpanID: nil,
            resource: [
                "agent.proof.marker": "perf-proof",
                "process.pid": "12345",
                "service.name": "AgentStudio",
            ],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.git.running.count": .int(4),
                "agentstudio.performance.git.status.duration_ms": .double(2.5),
                "agentstudio.performance.git.status.elapsed_ms": .double(2.7),
                "agentstudio.performance.git.status_unavailable.reason": .string("timeout"),
                "agentstudio.performance.git.root_path": .string("/Users/shravan/private/repo"),
                "agentstudio.performance.repo.dynamic_key.count": .int(999),
                "agentstudio.performance.future.elapsed_ms": .double(999),
                "agentstudio.performance.future.has_value": .bool(true),
                "agentstudio.performance.atom.kind": .string("entity_map"),
                "agentstudio.performance.atom.operation": .string("value"),
                "agentstudio.performance.atom.slot.count": .int(2),
                "agentstudio.performance.atom.cached_key.count": .int(1),
                "agentstudio.performance.atom.cache_hit": .bool(false),
                "agentstudio.performance.coordinator.activity_write.count": .int(3),
                "agentstudio.performance.coordinator.filesystem_source_elapsed_ms": .double(4.5),
                "agentstudio.performance.coordinator.index_elapsed_ms": .double(5.5),
                "agentstudio.performance.coordinator.mainactor_apply_elapsed_ms": .double(0.5),
                "agentstudio.performance.coordinator.phase": .string("source_sync"),
                "agentstudio.performance.coordinator.total_elapsed_ms": .double(10.5),
                "agentstudio.performance.management_layer.command": .string("toggleManagementLayer"),
                "agentstudio.performance.note_text": .string("raw payload should stay local"),
                "agentstudio.performance.pane_action.name": .string("minimizePane"),
                "agentstudio.performance.sidebar.is_collapsed": .bool(true),
                "agentstudio.performance.sidebar.split_width": .double(1200),
                "agentstudio.performance.sidebar.toggle.intent": .string("collapse"),
                "agentstudio.performance.sidebar.was_collapsed": .bool(false),
                "agentstudio.performance.sidebar.width": .double(320),
                "agentstudio.performance.terminal.geometry.reason": .string("splitViewDidResizeSubviews"),
                "agentstudio.performance.terminal.geometry.visible_terminal.count": .double(7),
                "agentstudio.performance.terminal.surface.cell_height_px": .double(28),
                "agentstudio.performance.terminal.surface.cell_width_px": .double(14),
                "agentstudio.performance.terminal.surface.column.count": .double(80),
                "agentstudio.performance.terminal.surface.current_height_px": .double(780),
                "agentstudio.performance.terminal.surface.current_width_px": .double(1200),
                "agentstudio.performance.terminal.surface.dedup_likely": .bool(false),
                "agentstudio.performance.terminal.surface.has_superview": .bool(true),
                "agentstudio.performance.terminal.surface.has_window": .bool(true),
                "agentstudio.performance.terminal.surface.hidden": .bool(false),
                "agentstudio.performance.terminal.surface.requested_height_px": .double(800),
                "agentstudio.performance.terminal.surface.requested_width_px": .double(1280),
                "agentstudio.performance.terminal.surface.row.count": .double(24),
                "agentstudio.performance.terminal.surface.source": .string("forceGeometrySync"),
                "agentstudio.trace.tag": .string("performance"),
                "agentstudio.worktree.id": .string(worktreeID.uuidString),
            ]
        )
    }

}
