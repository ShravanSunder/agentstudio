import Foundation
import Testing

@Suite("Bridge full-pyramid smoke verifier scripts")
struct BridgeFullPyramidSmokeVerifierScriptTests {
    @Test("review-journey verifier is wired through mise and asserts selection telemetry budgets")
    func reviewJourneyVerifierIsWiredThroughMiseAndAssertsSelectionTelemetryBudgets() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let script = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "scripts/verify-bridge-review-journey-smoke.sh"),
            encoding: .utf8
        )
        let mise = try String(contentsOf: projectRoot.appendingPathComponent(".mise.toml"), encoding: .utf8)

        #expect(mise.contains("[tasks.verify-bridge-review-journey-smoke]"))
        #expect(mise.contains("/bin/bash scripts/verify-bridge-review-journey-smoke.sh"))
        #expect(script.contains("#!/bin/bash"))
        #expect(script.contains("--dry-run"))
        #expect(script.contains("bridge-review-observability-smoke"))
        #expect(script.contains("AGENTSTUDIO_OBSERVABILITY_ALLOW_COMPLETED_EXIT=1"))
        #expect(script.contains("scripts/verify-debug-observability.sh"))
        #expect(script.contains("agent.proof.marker"))
        #expect(script.contains("performance.bridge.web.selected_content_painted"))
        #expect(script.contains("selected_content_painted fires exactly once per selection"))
        #expect(script.contains("performance.bridge.web.selected_content_dropped"))
        #expect(script.contains("revision_churn"))
        #expect(script.contains("performance.bridge.swift.content_load"))
        #expect(script.contains("AGENTSTUDIO_BRIDGE_REVIEW_JOURNEY_CONTENT_LOAD_CEILING"))
        #expect(script.contains("performance.bridge.web.telemetry_drop"))
        #expect(script.contains("AGENTSTUDIO_BRIDGE_TELEMETRY_DROP_STORM_THRESHOLD"))
    }

    @Test("mode-idle verifier is wired through mise and asserts mode gating stability")
    func modeIdleVerifierIsWiredThroughMiseAndAssertsModeGatingStability() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let script = try String(
            contentsOf: projectRoot.appendingPathComponent("scripts/verify-bridge-mode-idle-smoke.sh"),
            encoding: .utf8
        )
        let mise = try String(contentsOf: projectRoot.appendingPathComponent(".mise.toml"), encoding: .utf8)

        #expect(mise.contains("[tasks.verify-bridge-mode-idle-smoke]"))
        #expect(mise.contains("/bin/bash scripts/verify-bridge-mode-idle-smoke.sh"))
        #expect(script.contains("#!/bin/bash"))
        #expect(script.contains("--dry-run"))
        #expect(script.contains("bridge-review-to-file-view-observability-smoke"))
        #expect(script.contains("scripts/verify-debug-observability.sh"))
        #expect(script.contains("AGENTSTUDIO_BRIDGE_IDLE_MINUTES"))
        #expect(script.contains("wait_for_idle_wall_coverage"))
        #expect(!script.contains("sleep "))
        #expect(script.contains("process alive at end"))
        #expect(script.contains("performance.bridge.swift.content_load"))
        #expect(script.contains("content_load rate is zero during idle"))
        #expect(script.contains("performance.bridge.web.worktree_file_intake_reject"))
        #expect(script.contains("agentstudio.bridge.reopen_signaled"))
        #expect(script.contains("performance.bridge.swift.active_viewer_mode_signal_rejected"))
        #expect(script.contains("stale_generation"))
        #expect(script.contains("stale_sequence"))
        #expect(script.contains("session_reset"))
        #expect(script.contains("OTLP exporter alive"))
    }

    @Test(
        "dry-run validates LogSQL wiring through a harmless VictoriaLogs probe",
        arguments: [
            "scripts/verify-bridge-review-journey-smoke.sh",
            "scripts/verify-bridge-mode-idle-smoke.sh",
        ]
    )
    func dryRunValidatesLogSQLWiringThroughHarmlessProbe(scriptPath: String) throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let queryLog = fixture.url("curl-query.log")
        let curl = try fixture.executable(
            "curl-dry-run-probe",
            """
            #!/bin/bash
            printf '%s\\n' "$*" >> "\(queryLog.path)"
            exit 0
            """
        )

        var environment = dryRunEnvironment(for: scriptPath)
        environment["AGENTSTUDIO_CURL_BIN"] = curl.path
        environment["AI_TOOLS_OBSERVABILITY_LOGS_QUERY_URL"] = "http://127.0.0.1:9428/select/logsql/query"

        let result = try fixture.runScript(
            scriptPath,
            arguments: ["--dry-run"],
            environment: environment
        )

        #expect(result.exitCode == 0, "stdout: \(result.stdout)")
        #expect(result.stdout.contains("dry-run ok"))
        let queries = try String(contentsOf: queryLog, encoding: .utf8)
        #expect(queries.contains("query="))
        #expect(queries.contains("agent.proof.marker"))
        #expect(queries.contains("limit 0"))
    }

    private func dryRunEnvironment(for scriptPath: String) -> [String: String] {
        if scriptPath.contains("review-journey") {
            return [
                "AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION": "bridge-review-observability-smoke",
                "AGENTSTUDIO_OBSERVABILITY_MARKER": "dry-run-review-marker",
            ]
        }
        return [
            "AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION": "bridge-review-to-file-view-observability-smoke",
            "AGENTSTUDIO_OBSERVABILITY_MARKER": "dry-run-idle-marker",
        ]
    }
}
