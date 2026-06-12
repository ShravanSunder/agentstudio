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
                "agentstudio.trace.name": "beta-observability-123",
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
        #expect(projection.attributes["agentstudio.trace.name"] == .string("beta-observability-123"))
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
                "agentstudio.pane.id": .string(paneID.uuidString),
                "agentstudio.surface.id": .string(surfaceID.uuidString),
                "agentstudio.terminal.startup.error": .string("Failed after command output: secret prompt"),
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
        #expect(projection.attributes["agentstudio.app.is_active"] == .bool(false))
        #expect(projection.attributes["agentstudio.display.count"] == .int(2))
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
                "git.branch": "feature/otel",
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
        #expect(projection.resource["dev.repo.hash"] == nil)
        #expect(projection.resource["dev.repo.name"] == nil)
        #expect(projection.resource["dev.worktree.hash"] == nil)
        #expect(projection.resource["git.branch"] == nil)
        #expect(projection.attributes["dev.repo.hash"] == .string("repo-hash"))
        #expect(projection.attributes["dev.worktree.hash"] == .string("worktree-hash"))
        #expect(projection.attributes["git.branch"] == .string("feature/otel"))
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
                "agentstudio.trace.name": "beta-observability-456",
                "dev.release.channel": "beta",
                "dev.repo.hash": "repo-hash",
                "dev.repo.name": "agent-studio",
                "dev.runtime.flavor": "beta",
                "dev.worktree.hash": "worktree-hash",
                "git.branch": "feature/otel",
                "service.name": "AgentStudio",
                "service.version": "0.0.54-beta.15",
            ],
            scope: .init(name: "agentstudio.runtime", version: "0.1.0"),
            attributes: [
                "agentstudio.runtime.event": .string("worktree_recorded")
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)

        #expect(projection.resource["dev.worktree.hash"] == nil)
        #expect(projection.attributes["agentstudio.event.time_unix_nano"] == .int(500))
        #expect(projection.attributes["agentstudio.release_channel"] == .string("beta"))
        #expect(projection.attributes["agentstudio.runtime_flavor"] == .string("beta"))
        #expect(projection.attributes["agentstudio.trace.name"] == .string("beta-observability-456"))
        #expect(projection.attributes["dev.release.channel"] == .string("beta"))
        #expect(projection.attributes["dev.repo.hash"] == .string("repo-hash"))
        #expect(projection.attributes["dev.repo.name"] == nil)
        #expect(projection.attributes["dev.runtime.flavor"] == .string("beta"))
        #expect(projection.attributes["dev.worktree.hash"] == .string("worktree-hash"))
        #expect(projection.attributes["git.branch"] == .string("feature/otel"))
        #expect(projection.attributes["service.version"] == .string("0.0.54-beta.15"))
        #expect(projection.attributes["service.name"] == nil)
    }

    @Test
    func performanceProjectionKeepsSafeNumericFieldsAndDropsUnsafeContext() {
        let worktreeID = UUID(uuidString: "6DE2BC87-AD1F-4271-96DD-7922D58612D5")!
        let record = AgentStudioTraceRecord(
            timeUnixNano: 600,
            severityText: .info,
            body: "performance.git.status",
            traceID: "trace-should-not-export",
            spanID: "span-should-not-export",
            parentSpanID: nil,
            resource: [
                "agentstudio.trace.name": "perf-proof",
                "process.pid": "12345",
                "service.name": "AgentStudio",
            ],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.git.running.count": .int(4),
                "agentstudio.performance.git.status.duration_ms": .double(2.5),
                "agentstudio.performance.git.status.elapsed_ms": .double(2.7),
                "agentstudio.performance.git.root_path": .string("/Users/shravan/private/repo"),
                "agentstudio.performance.management_layer.command": .string("toggleManagementLayer"),
                "agentstudio.performance.note_text": .string("raw payload should stay local"),
                "agentstudio.performance.pane_action.name": .string("minimizePane"),
                "agentstudio.performance.sidebar.is_collapsed": .bool(true),
                "agentstudio.performance.sidebar.split_width": .double(1200),
                "agentstudio.performance.sidebar.toggle.intent": .string("collapse"),
                "agentstudio.performance.sidebar.was_collapsed": .bool(false),
                "agentstudio.performance.sidebar.width": .double(320),
                "agentstudio.trace.tag": .string("performance"),
                "agentstudio.worktree.id": .string(worktreeID.uuidString),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)
        let renderedProjection = projection.renderedForCanaryAssertions()

        #expect(projection.body == "performance.git.status")
        #expect(projection.attributes["agentstudio.trace.name"] == .string("perf-proof"))
        #expect(projection.attributes["agentstudio.trace.tag"] == .string("performance"))
        #expect(projection.attributes["agentstudio.performance.git.running.count"] == .int(4))
        #expect(projection.attributes["agentstudio.performance.git.status.duration_ms"] == .double(2.5))
        #expect(projection.attributes["agentstudio.performance.git.status.elapsed_ms"] == .double(2.7))
        #expect(projection.attributes["agentstudio.performance.git.root_path"] == nil)
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
        #expect(projection.attributes["agentstudio.worktree.id"] == nil)
        #expect(projection.resource["process.pid"] == nil)
        #expect(!renderedProjection.contains("/Users/shravan"))
        #expect(!renderedProjection.contains(worktreeID.uuidString))
    }
}

extension AgentStudioOTLPProjectedLogRecord {
    fileprivate func renderedForCanaryAssertions() -> String {
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
        return components.joined(separator: "\n")
    }
}
