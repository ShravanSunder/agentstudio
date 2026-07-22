import Foundation
import Testing

@testable import AgentStudio

@Suite
struct AgentStudioOTLPTraceProjectionTests {
    @Test
    func startupProjectionKeepsControlledFieldsAndDropsProcessIdentity() {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 100,
            severityText: .info,
            body: "app.startup.ghostty_init",
            traceID: "trace-should-not-export",
            spanID: "span-should-not-export",
            parentSpanID: "parent-should-not-export",
            resource: [
                "agentstudio.build.config": "DEBUG",
                "agentstudio.session.id": "session-1",
                "agent.proof.launch": "launch-token-123",
                "agent.proof.marker": "beta-observability-123",
                "process.pid": "1234",
                "service.name": "AgentStudio",
                "service.version": "0.0.99",
            ],
            scope: .init(name: "agentstudio.app.startup", version: "0.1.0"),
            attributes: [
                "agentstudio.app.startup.phase": .string("ghostty_init"),
                "agentstudio.app.startup.outcome": .string("succeeded"),
                "agentstudio.ghostty.status": .int(0),
                "agentstudio.trace.tag": .string("app.startup"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)

        #expect(projection.body == "app.startup.ghostty_init")
        #expect(projection.resource["service.name"] == "AgentStudio")
        #expect(projection.resource["service.version"] == "0.0.99")
        #expect(projection.resource["agentstudio.build.config"] == "DEBUG")
        #expect(projection.resource["agent.proof.launch"] == "launch-token-123")
        #expect(projection.attributes["agent.proof.launch"] == .string("launch-token-123"))
        #expect(projection.attributes["agent.proof.marker"] == .string("beta-observability-123"))
        #expect(projection.resource["process.pid"] == nil)
        #expect(projection.resource["agentstudio.session.id"] == nil)
        #expect(projection.attributes["agentstudio.app.startup.phase"] == .string("ghostty_init"))
        #expect(projection.attributes["agentstudio.app.startup.outcome"] == .string("succeeded"))
        #expect(projection.attributes["agentstudio.event.time_unix_nano"] == .int(100))
        #expect(projection.attributes["agentstudio.ghostty.status"] == .int(0))
        #expect(projection.traceID == nil)
        #expect(projection.spanID == nil)
    }

    @Test
    func bridgeProjectionPreservesValidTraceFieldsAndSafeAttributes() {
        let historicalBridgeLane = ["agentstudio", "bridge", "lane"].joined(separator: ".")
        let record = AgentStudioTraceRecord(
            timeUnixNano: 125,
            severityText: .info,
            body: "performance.bridge.webkit.push_envelope",
            traceID: "11111111111111111111111111111111",
            spanID: "2222222222222222",
            parentSpanID: "3333333333333333",
            resource: [
                "agentstudio.trace.name": "bridge-proof",
                "service.name": "AgentStudio",
            ],
            scope: .init(name: "agentstudio.bridge.performance.webkit", version: "0.1.0"),
            attributes: [
                "agentstudio.bridge.content.byte_size_bucket": .int(100_000),
                "agentstudio.bridge.content.line_count_bucket": .int(500),
                "agentstudio.bridge.header_supported": .bool(true),
                "agentstudio.bridge.item_id": .string("private-item-id"),
                historicalBridgeLane: .string("warm"),
                "agentstudio.bridge.phase": .string("transport"),
                "agentstudio.bridge.plane": .string("data"),
                "agentstudio.bridge.priority": .string("cold"),
                "agentstudio.bridge.slice": .string("review_metadata"),
                "agentstudio.bridge.transport": .string("push"),
                "agentstudio.performance.elapsed_ms": .double(4.25),
                "agentstudio.trace.tag": .string("bridge.performance.webkit"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)
        let renderedProjection = projection.renderedForCanaryAssertions()

        #expect(projection.traceID == "11111111111111111111111111111111")
        #expect(projection.spanID == "2222222222222222")
        #expect(projection.parentSpanID == "3333333333333333")
        #expect(projection.attributes["agentstudio.bridge.content.byte_size_bucket"] == .int(100_000))
        #expect(projection.attributes["agentstudio.bridge.content.line_count_bucket"] == .int(500))
        #expect(projection.attributes["agentstudio.bridge.header_supported"] == .bool(true))
        #expect(projection.attributes[historicalBridgeLane] == nil)
        #expect(projection.attributes["agentstudio.bridge.phase"] == .string("transport"))
        #expect(projection.attributes["agentstudio.bridge.plane"] == .string("data"))
        #expect(projection.attributes["agentstudio.bridge.priority"] == .string("cold"))
        #expect(projection.attributes["agentstudio.bridge.slice"] == .string("review_metadata"))
        #expect(projection.attributes["agentstudio.bridge.transport"] == .string("push"))
        #expect(projection.attributes["agentstudio.performance.elapsed_ms"] == .double(4.25))
        #expect(projection.attributes["agentstudio.bridge.item_id"] == nil)
        #expect(!renderedProjection.contains("private-item-id"))
    }

    @Test
    func bridgeProjectionDropsInvalidTaxonomyValues() {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 126,
            severityText: .info,
            body: "performance.bridge.webkit.push_envelope",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: [
                "service.name": "AgentStudio"
            ],
            scope: .init(name: "agentstudio.bridge.performance.webkit", version: "0.1.0"),
            attributes: [
                "agentstudio.bridge.phase": .string("package_push"),
                "agentstudio.bridge.plane": .string("file:///Users/private/repo"),
                "agentstudio.bridge.priority": .string("urgent"),
                "agentstudio.bridge.slice": .string("Sources/App/View.swift"),
                "agentstudio.trace.tag": .string("bridge.performance.webkit"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)
        let renderedProjection = projection.renderedForCanaryAssertions()

        #expect(projection.attributes["agentstudio.bridge.phase"] == nil)
        #expect(projection.attributes["agentstudio.bridge.plane"] == nil)
        #expect(projection.attributes["agentstudio.bridge.priority"] == nil)
        #expect(projection.attributes["agentstudio.bridge.slice"] == nil)
        #expect(!renderedProjection.contains("/Users/private/repo"))
        #expect(!renderedProjection.contains("Sources/App/View.swift"))
    }

    @Test
    func bridgeProjectionDropsInvalidTraceFields() {
        let historicalBridgeLane = ["agentstudio", "bridge", "lane"].joined(separator: ".")
        let record = AgentStudioTraceRecord(
            timeUnixNano: 126,
            severityText: .info,
            body: "performance.bridge.web.push_apply",
            traceID: "00000000000000000000000000000000",
            spanID: "not-a-span",
            parentSpanID: "0000000000000000",
            resource: [
                "service.name": "AgentStudio"
            ],
            scope: .init(name: "agentstudio.bridge.performance.web", version: "0.1.0"),
            attributes: [
                historicalBridgeLane: .string("warm"),
                "agentstudio.bridge.phase": .string("package_apply"),
                "agentstudio.trace.tag": .string("bridge.performance.web"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)

        #expect(projection.traceID == nil)
        #expect(projection.spanID == nil)
        #expect(projection.parentSpanID == nil)
    }

    @Test
    func sidebarPerformanceProjectionKeepsControlledTaxonomyAndDropsPayloadText() {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 175,
            severityText: .info,
            body: "performance.sidebar.projection",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: [
                "service.name": "AgentStudio"
            ],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.elapsed_ms": .double(2.75),
                "agentstudio.performance.sidebar.surface": .string("inbox"),
                "agentstudio.performance.sidebar.phase": .string("mainactor_apply"),
                "agentstudio.performance.sidebar.query_state": .string("non_empty"),
                "agentstudio.performance.sidebar.group_mode": .string("not_applicable"),
                "agentstudio.performance.sidebar.trigger": .string("grouping_switch"),
                "agentstudio.performance.sidebar.input.count": .int(10),
                "agentstudio.performance.sidebar.group.count": .int(3),
                "agentstudio.performance.sidebar.request_build_mainactor_elapsed_ms": .double(0.5),
                "agentstudio.performance.sidebar.section.count": .int(99),
                "agentstudio.performance.sidebar.mainactor_apply_elapsed_ms": .double(2.75),
                "agentstudio.performance.sidebar.notification_text": .string("secret user prompt"),
                "agentstudio.performance.sidebar.query_text": .string("billing secret"),
                "agentstudio.performance.sidebar.repo.id": .string(UUID().uuidString),
                "agentstudio.trace.tag": .string("performance"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)
        let renderedProjection = projection.renderedForCanaryAssertions()

        #expect(projection.body == "performance.sidebar.projection")
        #expect(projection.attributes["agentstudio.performance.sidebar.surface"] == .string("inbox"))
        #expect(projection.attributes["agentstudio.performance.sidebar.phase"] == .string("mainactor_apply"))
        #expect(projection.attributes["agentstudio.performance.sidebar.query_state"] == .string("non_empty"))
        #expect(projection.attributes["agentstudio.performance.sidebar.group_mode"] == .string("not_applicable"))
        #expect(projection.attributes["agentstudio.performance.sidebar.trigger"] == .string("grouping_switch"))
        #expect(projection.attributes["agentstudio.performance.sidebar.input.count"] == .int(10))
        #expect(projection.attributes["agentstudio.performance.sidebar.group.count"] == .int(3))
        #expect(
            projection.attributes["agentstudio.performance.sidebar.request_build_mainactor_elapsed_ms"] == .double(0.5))
        #expect(projection.attributes["agentstudio.performance.sidebar.section.count"] == nil)
        #expect(projection.attributes["agentstudio.performance.sidebar.mainactor_apply_elapsed_ms"] == .double(2.75))
        #expect(projection.attributes["agentstudio.performance.sidebar.notification_text"] == nil)
        #expect(projection.attributes["agentstudio.performance.sidebar.query_text"] == nil)
        #expect(projection.attributes["agentstudio.performance.sidebar.repo.id"] == nil)
        #expect(!renderedProjection.contains("secret user prompt"))
        #expect(!renderedProjection.contains("billing secret"))
    }

    @Test
    func sidebarRowIndexProjectionKeepsCanonicalPhaseAndElapsedKey() {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 176,
            severityText: .info,
            body: "performance.sidebar.row_index",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.elapsed_ms": .double(1.25),
                "agentstudio.performance.sidebar.surface": .string("repo"),
                "agentstudio.performance.sidebar.phase": .string("row_index"),
                "agentstudio.performance.sidebar.query_state": .string("empty"),
                "agentstudio.performance.sidebar.group_mode": .string("pane"),
                "agentstudio.performance.sidebar.trigger": .string("grouping_switch"),
                "agentstudio.performance.sidebar.row_index_elapsed_ms": .double(1.25),
                "agentstudio.performance.sidebar.row_index_worker_elapsed_ms": .double(99),
                "agentstudio.trace.tag": .string("performance"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)

        #expect(projection.body == "performance.sidebar.row_index")
        #expect(projection.attributes["agentstudio.performance.sidebar.phase"] == .string("row_index"))
        #expect(projection.attributes["agentstudio.performance.sidebar.trigger"] == .string("grouping_switch"))
        #expect(projection.attributes["agentstudio.performance.sidebar.row_index_elapsed_ms"] == .double(1.25))
        #expect(projection.attributes["agentstudio.performance.sidebar.row_index_worker_elapsed_ms"] == nil)
    }

    @Test
    func sidebarRequestBuildProjectionKeepsCanonicalPhaseAndDataRefreshTrigger() {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 177,
            severityText: .info,
            body: "performance.sidebar.projection",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.elapsed_ms": .double(0.75),
                "agentstudio.performance.sidebar.surface": .string("repo"),
                "agentstudio.performance.sidebar.phase": .string("request_build_mainactor"),
                "agentstudio.performance.sidebar.query_state": .string("empty"),
                "agentstudio.performance.sidebar.group_mode": .string("pane"),
                "agentstudio.performance.sidebar.trigger": .string("data_refresh"),
                "agentstudio.performance.sidebar.request_build_mainactor_elapsed_ms": .double(0.75),
                "agentstudio.trace.tag": .string("performance"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)

        #expect(projection.attributes["agentstudio.performance.sidebar.phase"] == .string("request_build_mainactor"))
        #expect(projection.attributes["agentstudio.performance.sidebar.trigger"] == .string("data_refresh"))
        #expect(
            projection.attributes["agentstudio.performance.sidebar.request_build_mainactor_elapsed_ms"] == .double(0.75)
        )
    }

    @Test
    func tccDiagnosticProjectionKeepsClassificationsAndDropsRawPaths() {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 179,
            severityText: .warn,
            body: "terminal.tcc.access_probe",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: [
                "service.name": "AgentStudio",
                "dev.release.channel": "beta",
            ],
            scope: .init(name: "agentstudio.terminal.tcc", version: "0.1.0"),
            attributes: [
                "agentstudio.tcc.phase": .string("startup_diagnostic"),
                "agentstudio.tcc.subject": .string("shell_child"),
                "agentstudio.tcc.access.target": .string("documents"),
                "agentstudio.tcc.access.result": .string("denied_eacces"),
                "agentstudio.tcc.responsible.kind": .string("agentstudio_beta"),
                "agentstudio.tcc.command.exit_class": .string("permission_denied"),
                "agentstudio.tcc.probe.sequence": .int(7),
                "agentstudio.tcc.bundle.changed": .bool(true),
                "agentstudio.tcc.bundle.executable.reachable": .bool(true),
                "agentstudio.tcc.tccdb.bundle_grant.present": .bool(true),
                "agentstudio.tcc.tccdb.path_row.count": .int(2),
                "agentstudio.tcc.raw.executable_path": .string(
                    "/Applications/AgentStudio Beta.app/Contents/MacOS/AgentStudio"),
                "agentstudio.tcc.raw.probe_path": .string("/Users/shravansunder/Documents/private"),
                "agentstudio.tcc.raw.responsible_path": .string(
                    "/Applications/AgentStudio Beta.app/Contents/MacOS/AgentStudio"),
                "agentstudio.tcc.tccdb.raw_client": .string("/Users/shravansunder/debug/AgentStudio"),
                "agentstudio.trace.tag": .string("terminal.tcc"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)
        let renderedProjection = projection.renderedForCanaryAssertions()

        #expect(projection.body == "terminal.tcc.access_probe")
        #expect(projection.attributes["agentstudio.trace.tag"] == .string("terminal.tcc"))
        #expect(projection.attributes["agentstudio.tcc.phase"] == .string("startup_diagnostic"))
        #expect(projection.attributes["agentstudio.tcc.subject"] == .string("shell_child"))
        #expect(projection.attributes["agentstudio.tcc.access.target"] == .string("documents"))
        #expect(projection.attributes["agentstudio.tcc.access.result"] == .string("denied_eacces"))
        #expect(projection.attributes["agentstudio.tcc.responsible.kind"] == .string("agentstudio_beta"))
        #expect(projection.attributes["agentstudio.tcc.command.exit_class"] == .string("permission_denied"))
        #expect(projection.attributes["agentstudio.tcc.probe.sequence"] == .int(7))
        #expect(projection.attributes["agentstudio.tcc.bundle.changed"] == .bool(true))
        #expect(projection.attributes["agentstudio.tcc.bundle.executable.reachable"] == .bool(true))
        #expect(projection.attributes["agentstudio.tcc.tccdb.bundle_grant.present"] == .bool(true))
        #expect(projection.attributes["agentstudio.tcc.tccdb.path_row.count"] == .int(2))
        #expect(projection.attributes["agentstudio.tcc.raw.executable_path"] == nil)
        #expect(projection.attributes["agentstudio.tcc.raw.probe_path"] == nil)
        #expect(projection.attributes["agentstudio.tcc.raw.responsible_path"] == nil)
        #expect(projection.attributes["agentstudio.tcc.tccdb.raw_client"] == nil)
        #expect(!renderedProjection.contains("/Users/shravansunder/Documents/private"))
        #expect(!renderedProjection.contains("AgentStudio Beta.app/Contents/MacOS/AgentStudio"))
    }

    @Test
    func fullDiskAccessHealthProjectionKeepsOnlySafeClassificationFields() {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 179,
            severityText: .warn,
            body: "app.full_disk_access.health_check.completed",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: [
                "service.name": "AgentStudio",
                "dev.release.channel": "beta",
            ],
            scope: .init(name: "agentstudio.app.startup", version: "0.1.0"),
            attributes: [
                "agentstudio.app.startup.phase": .string("full_disk_access_health_check"),
                "agentstudio.app.startup.outcome": .string("blocked"),
                "agentstudio.full_disk_access.health.healthy": .bool(false),
                "agentstudio.tcc.access.target": .string("messages_data"),
                "agentstudio.tcc.access.result": .string("denied_eperm"),
                "agentstudio.tcc.command.exit_class": .string("permission_denied"),
                "agentstudio.tcc.raw.probe_path": .string("/Users/shravansunder/Library/Messages"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)
        let renderedProjection = projection.renderedForCanaryAssertions()

        #expect(projection.body == "app.full_disk_access.health_check.completed")
        #expect(projection.attributes["agentstudio.app.startup.phase"] == .string("full_disk_access_health_check"))
        #expect(projection.attributes["agentstudio.app.startup.outcome"] == .string("blocked"))
        #expect(projection.attributes["agentstudio.full_disk_access.health.healthy"] == .bool(false))
        #expect(projection.attributes["agentstudio.tcc.access.target"] == .string("messages_data"))
        #expect(projection.attributes["agentstudio.tcc.access.result"] == .string("denied_eperm"))
        #expect(projection.attributes["agentstudio.tcc.command.exit_class"] == .string("permission_denied"))
        #expect(projection.attributes["agentstudio.tcc.raw.probe_path"] == nil)
        #expect(!renderedProjection.contains("/Users/shravansunder/Library/Messages"))
    }
}

@Suite
struct AgentStudioOTLPTraceProjectionSanitizationTests {

    @Test
    func persistenceProjectionDropsPathsWorkspaceIDsAndRawErrors() {
        let workspaceID = UUID(uuidString: "F6ADCB1B-E191-4890-963E-37F4A694B065")!
        let record = AgentStudioTraceRecord(
            timeUnixNano: 200,
            severityText: .error,
            body: "persistence.recovery",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: [
                "service.name": "AgentStudio"
            ],
            scope: .init(name: "agentstudio.persistence.recovery", version: "0.1.0"),
            attributes: [
                "agentstudio.persistence.backend": .string("sqlite"),
                "agentstudio.persistence.error.description": .string(
                    "SQLite failed at /Users/shravan/private/core.sqlite"
                ),
                "agentstudio.persistence.lane": .string("local"),
                "agentstudio.persistence.operation": .string("workspace.load"),
                "agentstudio.persistence.outcome": .string("quarantined"),
                "agentstudio.persistence.phase": .string("quarantine_sidecars"),
                "agentstudio.persistence.recovery.kind": .string("local_quarantine"),
                "agentstudio.sqlite.database": .string("local"),
                "agentstudio.sqlite.database_path": .string("~/Library/Application Support/AgentStudio/core.sqlite"),
                "agentstudio.trace.tag": .string("persistence.recovery"),
                "agentstudio.workspace.id": .string(workspaceID.uuidString),
                "agentstudio.workspace.snapshot.has_tab_membership_mismatch": .bool(true),
                "agentstudio.workspace.snapshot.pane_count": .int(2),
                "agentstudio.workspace.snapshot.tab_membership_mismatches": .stringArray([workspaceID.uuidString]),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)
        let renderedProjection = projection.renderedForCanaryAssertions()

        #expect(projection.attributes["agentstudio.persistence.backend"] == .string("sqlite"))
        #expect(projection.attributes["agentstudio.persistence.recovery.kind"] == .string("local_quarantine"))
        #expect(projection.attributes["agentstudio.workspace.snapshot.has_tab_membership_mismatch"] == .bool(true))
        #expect(projection.attributes["agentstudio.workspace.snapshot.pane_count"] == .int(2))
        #expect(projection.attributes["agentstudio.workspace.id"] == nil)
        #expect(projection.attributes["agentstudio.sqlite.database_path"] == nil)
        #expect(projection.attributes["agentstudio.persistence.error.description"] == nil)
        #expect(projection.attributes["agentstudio.workspace.snapshot.tab_membership_mismatches"] == nil)
        #expect(!renderedProjection.contains("/Users/shravan"))
        #expect(!renderedProjection.contains(workspaceID.uuidString))
    }

    @Test
    func terminalProjectionDropsPaneSurfaceZmxAndRawFailureDetails() {
        let paneID = UUID(uuidString: "E568C446-9E0F-445B-95C9-382AE44915D5")!
        let surfaceID = UUID(uuidString: "D2C553E9-31C1-4A9C-9DD4-2D5255B8EEC3")!
        let record = AgentStudioTraceRecord(
            timeUnixNano: 300,
            severityText: .warn,
            body: "terminal.startup.surface_create_failed",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: [
                "service.name": "AgentStudio"
            ],
            scope: .init(name: "agentstudio.terminal.startup", version: "0.1.0"),
            attributes: [
                "agentstudio.app.is_active": .bool(false),
                "agentstudio.display.count": .int(2),
                "agentstudio.ghostty.surface.environment_variable_count": .int(4),
                "agentstudio.ghostty.surface.initial_frame_height": .double(700),
                "agentstudio.ghostty.surface.initial_frame_width": .double(1100),
                "agentstudio.ghostty.surface.startup_command_present": .bool(true),
                "agentstudio.pane.id": .string(paneID.uuidString),
                "agentstudio.surface.id": .string(surfaceID.uuidString),
                "agentstudio.terminal.startup.error": .string("Failed after command output: secret prompt"),
                "agentstudio.terminal.startup.failure.creation_retry.count": .int(2),
                "agentstudio.terminal.startup.failure.kind": .string("creation_failed"),
                "agentstudio.terminal.startup.operation_id": .string(UUID().uuidString),
                "agentstudio.terminal.startup.outcome": .string("failed"),
                "agentstudio.terminal.startup.phase": .string("surface_create_failed"),
                "agentstudio.trace.tag": .string("terminal.startup"),
                "agentstudio.zmx.session_id": .string("zmx-private-session"),
                "agentstudio.zmx.socket_path_headroom": .int(-2),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)
        let renderedProjection = projection.renderedForCanaryAssertions()

        #expect(projection.attributes["agentstudio.terminal.startup.phase"] == .string("surface_create_failed"))
        #expect(projection.attributes["agentstudio.terminal.startup.outcome"] == .string("failed"))
        #expect(projection.attributes["agentstudio.terminal.startup.failure.kind"] == .string("creation_failed"))
        #expect(projection.attributes["agentstudio.terminal.startup.failure.creation_retry.count"] == .int(2))
        #expect(projection.attributes["agentstudio.app.is_active"] == .bool(false))
        #expect(projection.attributes["agentstudio.display.count"] == .int(2))
        #expect(projection.attributes["agentstudio.ghostty.surface.environment_variable_count"] == .int(4))
        #expect(projection.attributes["agentstudio.ghostty.surface.initial_frame_height"] == .double(700))
        #expect(projection.attributes["agentstudio.ghostty.surface.initial_frame_width"] == .double(1100))
        #expect(projection.attributes["agentstudio.ghostty.surface.startup_command_present"] == .bool(true))
        #expect(projection.attributes["agentstudio.zmx.socket_path_headroom"] == .int(-2))
        #expect(projection.attributes["agentstudio.pane.id"] == nil)
        #expect(projection.attributes["agentstudio.surface.id"] == nil)
        #expect(projection.attributes["agentstudio.terminal.startup.error"] == nil)
        #expect(projection.attributes["agentstudio.terminal.startup.operation_id"] == nil)
        #expect(projection.attributes["agentstudio.zmx.session_id"] == nil)
        #expect(!renderedProjection.contains(paneID.uuidString))
        #expect(!renderedProjection.contains(surfaceID.uuidString))
        #expect(!renderedProjection.contains("secret prompt"))
    }

    @Test
    func terminalActivityProjectionKeepsAgentHeuristicEvidenceAndDropsPaneIdentity() {
        let paneID = UUID(uuidString: "B25FE4D0-67D6-495B-A93F-8E9E6FF311DD")!
        let record = AgentStudioTraceRecord(
            timeUnixNano: 325,
            severityText: .info,
            body: "terminal.activity.unseenWindowClosed",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: [
                "agent.proof.marker": "terminal-agent-settled-proof",
                "service.name": "AgentStudio",
            ],
            scope: .init(name: "agentstudio.terminal.activity", version: "0.1.0"),
            attributes: [
                "agentstudio.pane.id": .string(paneID.uuidString),
                "agentstudio.trace.tag": .string("terminal.activity"),
                "terminal.activity.baseline_rows": .int(100),
                "terminal.activity.close_reason": .string("quiet"),
                "terminal.activity.debounce_ms": .int(180_000),
                "terminal.activity.duration_ms": .int(61_000),
                "terminal.activity.event_count": .int(2),
                "terminal.activity.is_agent_candidate": .bool(true),
                "terminal.activity.is_agent_settled_candidate": .bool(true),
                "terminal.activity.is_inferred": .bool(true),
                "terminal.activity.is_pinned_to_bottom": .bool(false),
                "terminal.activity.latest_rows": .int(700),
                "terminal.activity.rows_added": .int(600),
                "terminal.activity.source": .string("scrollbar"),
                "terminal.activity.threshold_rows": .int(30),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)
        let renderedProjection = projection.renderedForCanaryAssertions()

        #expect(projection.attributes["agentstudio.trace.tag"] == .string("terminal.activity"))
        #expect(projection.attributes["terminal.activity.close_reason"] == .string("quiet"))
        #expect(projection.attributes["terminal.activity.is_agent_candidate"] == .bool(true))
        #expect(projection.attributes["terminal.activity.is_agent_settled_candidate"] == .bool(true))
        #expect(projection.attributes["terminal.activity.rows_added"] == .int(600))
        #expect(projection.attributes["agentstudio.pane.id"] == nil)
        #expect(!renderedProjection.contains(paneID.uuidString))
    }

    @Test
    func terminalSignalProjectionKeepsControlledSignalFieldsAndDropsRawPayloadAndIDs() {
        let paneID = UUID(uuidString: "1A84D2E8-4177-4D6B-8360-2BAA4C08654A")!
        let surfaceID = UUID(uuidString: "7F609C1D-B01C-4D9B-B8D7-BC566B42716F")!
        let record = AgentStudioTraceRecord(
            timeUnixNano: 350,
            severityText: .info,
            body: "ghostty.action.translated",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: [
                "agent.proof.marker": "terminal-signal-proof",
                "service.name": "AgentStudio",
            ],
            scope: .init(name: "agentstudio.terminal.signal", version: "0.1.0"),
            attributes: [
                "agentstudio.ghostty.action.name": .string("desktopNotification"),
                "agentstudio.ghostty.action.payload": .string("desktopNotification"),
                "agentstudio.ghostty.action.tag": .int(25),
                "agentstudio.ghostty.route.reason": .string("runtime_event_delivered"),
                "agentstudio.ghostty.route.result": .bool(true),
                "agentstudio.ghostty.signal.class": .string("semantic"),
                "agentstudio.pane.id": .string(paneID.uuidString),
                "agentstudio.runtime.event": .string("terminal.desktopNotificationRequested"),
                "agentstudio.surface.id": .string(surfaceID.uuidString),
                "agentstudio.trace.tag": .string("terminal.signal"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)
        let renderedProjection = projection.renderedForCanaryAssertions()

        #expect(projection.attributes["agentstudio.trace.tag"] == .string("terminal.signal"))
        #expect(projection.attributes["agentstudio.ghostty.action.name"] == .string("desktopNotification"))
        #expect(projection.attributes["agentstudio.ghostty.action.tag"] == .int(25))
        #expect(projection.attributes["agentstudio.ghostty.route.reason"] == .string("runtime_event_delivered"))
        #expect(projection.attributes["agentstudio.ghostty.route.result"] == .bool(true))
        #expect(projection.attributes["agentstudio.ghostty.signal.class"] == .string("semantic"))
        #expect(projection.attributes["agentstudio.runtime.event"] == .string("terminal.desktopNotificationRequested"))
        #expect(projection.attributes["agentstudio.ghostty.action.payload"] == nil)
        #expect(projection.attributes["agentstudio.pane.id"] == nil)
        #expect(projection.attributes["agentstudio.surface.id"] == nil)
        #expect(!renderedProjection.contains(paneID.uuidString))
        #expect(!renderedProjection.contains(surfaceID.uuidString))
    }

    @Test
    func notificationProjectionKeepsRoutingEvidenceAndDropsNotificationIdentity() {
        let notificationID = UUID(uuidString: "55461083-7987-4CA6-982E-1D0BB15AF2E1")!
        let sessionID = UUID(uuidString: "13955374-46E1-43B8-AD8E-D60F1F59631A")!
        let record = AgentStudioTraceRecord(
            timeUnixNano: 375,
            severityText: .info,
            body: "inbox.notification.appended",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: [
                "agent.proof.marker": "inbox-proof",
                "service.name": "AgentStudio",
            ],
            scope: .init(name: "agentstudio.inbox", version: "0.1.0"),
            attributes: [
                "agentstudio.inbox.claim.lane": .string("pane"),
                "agentstudio.inbox.claim.semantic": .string("activity"),
                "agentstudio.inbox.claim.session_id": .string(sessionID.uuidString),
                "agentstudio.inbox.decision": .string("promote"),
                "agentstudio.inbox.global_unread_after": .int(3),
                "agentstudio.inbox.global_unread_before": .int(2),
                "agentstudio.inbox.global_unread_count": .int(3),
                "agentstudio.inbox.kind": .string("unseenActivity"),
                "agentstudio.inbox.notification.coalesced": .bool(true),
                "agentstudio.inbox.notification.id": .string(notificationID.uuidString),
                "agentstudio.inbox.notification.revoked": .bool(true),
                "agentstudio.inbox.reason": .string("unattended_pane"),
                "agentstudio.pane.attended": .bool(false),
                "agentstudio.pane.observed": .bool(false),
                "agentstudio.pane.pinned_to_bottom": .bool(true),
                "agentstudio.pane_inbox.cleared_count": .int(1),
                "agentstudio.pane_inbox.dismissed": .bool(true),
                "agentstudio.pane_inbox.keep_count": .int(2),
                "agentstudio.trace.tag": .string("inbox"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)
        let renderedProjection = projection.renderedForCanaryAssertions()

        #expect(projection.attributes["agentstudio.inbox.claim.lane"] == .string("pane"))
        #expect(projection.attributes["agentstudio.inbox.claim.semantic"] == .string("activity"))
        #expect(projection.attributes["agentstudio.inbox.decision"] == .string("promote"))
        #expect(projection.attributes["agentstudio.inbox.global_unread_after"] == .int(3))
        #expect(projection.attributes["agentstudio.inbox.global_unread_before"] == .int(2))
        #expect(projection.attributes["agentstudio.inbox.global_unread_count"] == .int(3))
        #expect(projection.attributes["agentstudio.inbox.kind"] == .string("unseenActivity"))
        #expect(projection.attributes["agentstudio.inbox.notification.coalesced"] == .bool(true))
        #expect(projection.attributes["agentstudio.inbox.notification.revoked"] == .bool(true))
        #expect(projection.attributes["agentstudio.inbox.reason"] == .string("unattended_pane"))
        #expect(projection.attributes["agentstudio.pane.attended"] == .bool(false))
        #expect(projection.attributes["agentstudio.pane.observed"] == .bool(false))
        #expect(projection.attributes["agentstudio.pane.pinned_to_bottom"] == .bool(true))
        #expect(projection.attributes["agentstudio.pane_inbox.cleared_count"] == .int(1))
        #expect(projection.attributes["agentstudio.pane_inbox.dismissed"] == .bool(true))
        #expect(projection.attributes["agentstudio.pane_inbox.keep_count"] == .int(2))
        #expect(projection.attributes["agentstudio.inbox.claim.session_id"] == nil)
        #expect(projection.attributes["agentstudio.inbox.notification.id"] == nil)
        #expect(!renderedProjection.contains(notificationID.uuidString))
        #expect(!renderedProjection.contains(sessionID.uuidString))
    }

    @Test
    func unsafeBodyFallsBackAndSafeIdentityKeysRemainAllowed() {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 400,
            severityText: .info,
            body: "raw output from /Users/shravan/private/project",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: [
                "dev.repo.hash": "repo-hash",
                "dev.repo.name": "agent-studio",
                "dev.worktree.hash": "worktree-hash",
                "dev.branch.name": "feature/otel",
                "service.name": "AgentStudio",
            ],
            scope: .init(name: "agentstudio.runtime", version: "0.1.0"),
            attributes: [
                "agentstudio.runtime.event": .string("session_state_changed"),
                "agentstudio.runtime.output": .string("raw output from /Users/shravan/private/project"),
                "agentstudio.trace.tag": .string("runtime"),
                "dev.runtime.flavor": .string("debug"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)
        let renderedProjection = projection.renderedForCanaryAssertions()

        #expect(projection.body == "agentstudio.trace.record")
        #expect(projection.resource["dev.repo.hash"] == "repo-hash")
        #expect(projection.resource["dev.repo.name"] == nil)
        #expect(projection.resource["dev.worktree.hash"] == "worktree-hash")
        #expect(projection.resource["dev.branch.name"] == "feature/otel")
        #expect(projection.attributes["dev.repo.hash"] == .string("repo-hash"))
        #expect(projection.attributes["dev.worktree.hash"] == .string("worktree-hash"))
        #expect(projection.attributes["dev.branch.name"] == .string("feature/otel"))
        #expect(projection.attributes["agentstudio.runtime.event"] == .string("session_state_changed"))
        #expect(projection.attributes["dev.runtime.flavor"] == .string("debug"))
        #expect(projection.attributes["agentstudio.runtime.output"] == nil)
        #expect(!renderedProjection.contains("/Users/shravan"))
    }

    @Test
    func safeResourceIdentityIsCopiedToPerRecordAttributesForLogStreaming() {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 500,
            severityText: .info,
            body: "runtime.worktree",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: [
                "agentstudio.release_channel": "beta",
                "agentstudio.runtime_flavor": "beta",
                "agent.proof.launch": "launch-token-456",
                "agent.proof.marker": "beta-observability-456",
                "dev.release.channel": "beta",
                "dev.repo.hash": "repo-hash",
                "dev.repo.name": "agent-studio",
                "dev.runtime.flavor": "beta",
                "dev.worktree.hash": "worktree-hash",
                "dev.branch.name": "feature/otel",
                "service.name": "AgentStudio",
                "service.version": "0.0.54-beta.15",
            ],
            scope: .init(name: "agentstudio.runtime", version: "0.1.0"),
            attributes: [
                "agentstudio.runtime.event": .string("worktree_recorded")
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)

        #expect(projection.resource["agent.proof.marker"] == "beta-observability-456")
        #expect(projection.resource["agent.proof.launch"] == "launch-token-456")
        #expect(projection.resource["dev.repo.hash"] == "repo-hash")
        #expect(projection.resource["dev.worktree.hash"] == "worktree-hash")
        #expect(projection.resource["dev.branch.name"] == "feature/otel")
        #expect(projection.attributes["agentstudio.event.time_unix_nano"] == .int(500))
        #expect(projection.attributes["agentstudio.release_channel"] == .string("beta"))
        #expect(projection.attributes["agentstudio.runtime_flavor"] == .string("beta"))
        #expect(projection.attributes["agent.proof.marker"] == .string("beta-observability-456"))
        #expect(projection.attributes["agent.proof.launch"] == .string("launch-token-456"))
        #expect(projection.attributes["dev.release.channel"] == .string("beta"))
        #expect(projection.attributes["dev.repo.hash"] == .string("repo-hash"))
        #expect(projection.attributes["dev.repo.name"] == nil)
        #expect(projection.attributes["dev.runtime.flavor"] == .string("beta"))
        #expect(projection.attributes["dev.worktree.hash"] == .string("worktree-hash"))
        #expect(projection.attributes["dev.branch.name"] == .string("feature/otel"))
        #expect(projection.attributes["service.version"] == .string("0.0.54-beta.15"))
        #expect(projection.attributes["service.name"] == nil)
    }

}

extension AgentStudioOTLPProjectedLogRecord {
    func renderedForCanaryAssertions() -> String {
        var components = [
            body,
            resource.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "),
            attributes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "),
        ]
        if let traceID {
            components.append(traceID)
        }
        if let spanID {
            components.append(spanID)
        }
        if let parentSpanID {
            components.append(parentSpanID)
        }
        return components.joined(separator: "\n")
    }
}
