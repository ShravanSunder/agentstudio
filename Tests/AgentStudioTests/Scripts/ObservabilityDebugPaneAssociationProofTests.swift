import Foundation
import Testing

@Suite("Observability debug pane association proof")
struct ObservabilityDebugPaneAssociationProofTests {
    @Test("debug verifier accepts complete pane association runtime proof and bounded outcomes")
    func acceptsCompletePaneAssociationRuntimeProof() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = try paneAssociationStateFile(fixture: fixture)
        let queryLog = fixture.url("curl-query.log")

        let result = try fixture.runVerifier(
            scriptPath: "scripts/verify-debug-observability.sh",
            stateFile: stateFile,
            environment: paneAssociationVerifierEnvironment(
                fixture: fixture,
                queryLog: queryLog,
                includesTopologyRemovedOutcome: true
            )
        )

        #expect(result.exitCode == 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        let queries = try String(contentsOf: queryLog, encoding: .utf8)
        #expect(queries.contains("agentstudio.startup_diagnostic.association_proof.succeeded"))
        #expect(queries.contains("agentstudio.startup_diagnostic.association.topology_orphan_succeeded"))
        #expect(queries.contains("performance.pane.association"))
        #expect(queries.contains("agentstudio.performance.pane.association_outcome"))
    }

    @Test("debug verifier rejects pane association proof without topology removal telemetry")
    func rejectsProofWithoutTopologyRemovalTelemetry() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = try paneAssociationStateFile(fixture: fixture)

        let result = try fixture.runVerifier(
            scriptPath: "scripts/verify-debug-observability.sh",
            stateFile: stateFile,
            environment: paneAssociationVerifierEnvironment(
                fixture: fixture,
                queryLog: fixture.url("curl-query.log"),
                includesTopologyRemovedOutcome: false
            )
        )

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("topology_removed"))
    }

    private func paneAssociationStateFile(fixture: LauncherScriptFixture) throws -> URL {
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=debug-marker
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=testcode
        AGENTSTUDIO_OBSERVABILITY_PID=999999999
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-08-16T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION=pane-association-runtime-proof
        AGENTSTUDIO_OBSERVABILITY_APP=\(shellEscapedStateValue(fixture.url("Agent Studio Debug testcode.app").path))
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)
        return stateFile
    }

    private func paneAssociationVerifierEnvironment(
        fixture: LauncherScriptFixture,
        queryLog: URL,
        includesTopologyRemovedOutcome: Bool
    ) throws -> [String: String] {
        let topologyRemovedRecord =
            includesTopologyRemovedOutcome
            ? #"{"_msg":"performance.pane.association","agentstudio.performance.pane.association_outcome":"topology_removed"}\n"#
            : ""
        let curl = try fixture.executable(
            "curl-pane-association-proof",
            """
            #!/bin/bash
            printf '%s\\n' "$*" >> "\(queryLog.path)"
            if [[ "$*" == *"app.did_finish_launching.succeeded"* ]]; then
              printf '{"_msg":"app.did_finish_launching.succeeded","agentstudio.app.startup.phase":"did_finish_launching","agentstudio.app.startup.outcome":"succeeded"}\\n'
              exit 0
            fi
            if [[ "$*" == *"app.startup_diagnostic_action.command_exercised"* ]] || [[ "$*" == *"app.startup_diagnostic_action.completed"* ]]; then
              printf '{"_msg":"app.startup_diagnostic_action.completed","agentstudio.startup_diagnostic.action":"pane-association-runtime-proof","agentstudio.startup_diagnostic.created_pane.count":2,"agentstudio.startup_diagnostic.association.initial_succeeded":true,"agentstudio.startup_diagnostic.association.cwd_move_succeeded":true,"agentstudio.startup_diagnostic.association.topology_clear_succeeded":true,"agentstudio.startup_diagnostic.association.topology_orphan_succeeded":true,"agentstudio.startup_diagnostic.association.topology_adopt_succeeded":true,"agentstudio.startup_diagnostic.association.free_pane_remained_nil":true,"agentstudio.startup_diagnostic.association_proof.succeeded":true}\\n'
              exit 0
            fi
            if [[ "$*" == *"performance.pane.association"* ]]; then
              printf '{"_msg":"performance.pane.association","agentstudio.performance.pane.association_outcome":"resolved_changed"}\\n'
              printf '{"_msg":"performance.pane.association","agentstudio.performance.pane.association_outcome":"free_nil"}\\n'
              printf '{"_msg":"performance.pane.association","agentstudio.performance.pane.association_outcome":"resolved_equal"}\\n'
              printf '\(topologyRemovedRecord)'
              exit 0
            fi
            if [[ "$*" == *":*"* ]]; then
              exit 0
            fi
            printf '{"service.name":"AgentStudio","service.version":"0.0.1-debug+testcode","dev.runtime.flavor":"debug","_msg":"app.process.start"}\\n'
            exit 0
            """
        )
        return [
            "AGENTSTUDIO_OBSERVABILITY_ALLOW_COMPLETED_EXIT": "1",
            "AGENTSTUDIO_OBSERVABILITY_VERIFY_ATTEMPTS": "1",
            "AGENTSTUDIO_OBSERVABILITY_VERIFY_RETRY_DELAY_SECONDS": "0",
            "AGENTSTUDIO_CURL_BIN": curl.path,
        ]
    }
}
