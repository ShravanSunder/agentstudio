import Darwin
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
        #expect(script.contains("performance.bridge.web.code_view_item_materialize"))
        #expect(script.contains("EXPECTED_SELECTED_MATERIALIZATIONS=\"$((EXPECTED_SELECTIONS - 1))\""))
        #expect(script.contains("code_view_item_materialize selected items materialize for selection-changing renders"))
        #expect(script.contains("performance.bridge.web.selected_content_painted"))
        #expect(script.contains("AGENTSTUDIO_BRIDGE_REVIEW_JOURNEY_CLICK_SELECTIONS"))
        #expect(script.contains("selected_content_painted fires exactly once per click-anchored selection"))
        #expect(
            script.contains("selected_content_painted materialize_ms present exactly once per click-anchored selection")
        )
        #expect(script.contains("agentstudio.startup_diagnostic.bridge.frame_liveness.raf_alive"))
        #expect(script.contains("skip_assertion"))
        #expect(script.contains("diagnostic_skipped_query"))
        #expect(script.contains("wait_for_log_query"))
        #expect(script.contains("is_frame_not_live_skip"))
        #expect(script.contains("frame_not_live"))
        #expect(script.contains("agentstudio.startup_diagnostic.render_proof.succeeded"))
        #expect(script.contains("raf_alive=false"))
        #expect(script.contains("wait_for_optional_log_query"))
        #expect(completedResponseAppearsBeforeSkippedResponse(in: script))
        #expect(script.contains("selected_content_painted skipped because requestAnimationFrame is not live"))
        #expect(script.contains("frame_liveness_raf_alive=$frame_liveness_raf_alive"))
        #expect(script.contains("agentstudio.bridge.selected_content.materialize_ms:*"))
        #expect(script.contains("performance.bridge.web.selection_commit"))
        #expect(script.contains("performance.bridge.web.selected_content_dropped"))
        #expect(script.contains("revision_churn"))
        #expect(script.contains("performance.bridge.swift.content_load"))
        #expect(script.contains("agentstudio.startup_diagnostic.bridge.review_expected_item.count"))
        #expect(script.contains("content_load count is at least explicit selections"))
        #expect(script.contains("content_load count bounded by diagnostic review_expected_item base/head role count"))
        #expect(script.contains("content_load count quiesced"))
        #expect(script.contains("AGENTSTUDIO_BRIDGE_REVIEW_JOURNEY_QUIESCENCE_SECONDS"))
        #expect(!script.contains("AGENTSTUDIO_BRIDGE_REVIEW_JOURNEY_CONTENT_LOAD_CEILING"))
        #expect(script.contains("performance.bridge.web.telemetry_drop"))
        #expect(script.contains(#"agentstudio.bridge.telemetry.drop_reason:!=\"stale_push\""#))
        #expect(script.contains("zero non-stale telemetry_drop storms"))
        #expect(script.contains("performance.bridge.swift.telemetry_sidecar_drain"))
        #expect(script.contains("nonterminal_reopened"))
        #expect(script.contains("terminal_closed"))
        #expect(script.contains("one nonterminal telemetry sidecar drain receipt"))
        #expect(script.contains("one terminal telemetry sidecar drain receipt"))
        #expect(script.contains("telemetry sidecar drain receipts share one session digest"))
        #expect(script.contains("agentstudio.bridge.telemetry.required_loss.count"))
        #expect(script.contains("agentstudio.bridge.telemetry.optional_loss.count"))
        #expect(script.contains("agentstudio.bridge.telemetry.worker_sequence_gap.count"))
        #expect(script.contains("agentstudio.bridge.telemetry.native_batch_sequence_gap.count"))
        #expect(script.contains("agentstudio.bridge.telemetry.proof_eligible"))
        #expect(script.contains("agentstudio.bridge.telemetry.lossy"))
        #expect(script.contains("agentstudio.bridge.telemetry.settlement_acknowledged"))
        #expect(script.contains("terminal accepted batch sequence covers nonterminal drain"))
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
        #expect(script.contains("agentstudio.startup_diagnostic.bridge.frame_liveness.raf_alive"))
        #expect(script.contains("diagnostic_skipped_query"))
        #expect(script.contains("wait_for_log_query"))
        #expect(script.contains("is_frame_not_live_skip"))
        #expect(script.contains("frame_not_live"))
        #expect(script.contains("agentstudio.startup_diagnostic.render_proof.succeeded"))
        #expect(script.contains("wait_for_optional_log_query"))
        #expect(completedResponseAppearsBeforeSkippedResponse(in: script))
        #expect(script.contains("time_to_first_interaction skipped because requestAnimationFrame is not live"))
        #expect(script.contains("frame_liveness_raf_alive=$frame_liveness_raf_alive"))
        #expect(script.contains("OTLP exporter alive"))
    }

    @Test("review-journey verifier accepts frame-not-live skip without miss noise")
    func reviewJourneyVerifierAcceptsFrameNotLiveSkipWithoutMissNoise() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = try writeStateFile(
            fixture: fixture,
            action: "bridge-review-observability-smoke"
        )

        let result = try fixture.runVerifier(
            scriptPath: "scripts/verify-bridge-review-journey-smoke.sh",
            stateFile: stateFile,
            environment: frameNotLiveSkipEnvironment(
                fixture: fixture,
                action: "bridge-review-observability-smoke",
                curlName: "curl-review-journey-frame-not-live"
            )
        )

        #expect(result.exitCode == 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        #expect(result.stdout.contains("review journey smoke skipped because startup frame is not live"))
        #expect(!result.stderr.contains("completed/skipped record missing"))
        #expect(!result.stderr.contains("skipped record missing"))
        #expect(!result.stderr.contains("did not complete successfully"))
    }

    @Test("mode-idle verifier accepts frame-not-live skip without miss noise")
    func modeIdleVerifierAcceptsFrameNotLiveSkipWithoutMissNoise() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = try writeStateFile(
            fixture: fixture,
            action: "bridge-review-to-file-view-observability-smoke"
        )

        let result = try fixture.runVerifier(
            scriptPath: "scripts/verify-bridge-mode-idle-smoke.sh",
            stateFile: stateFile,
            environment: frameNotLiveSkipEnvironment(
                fixture: fixture,
                action: "bridge-review-to-file-view-observability-smoke",
                curlName: "curl-mode-idle-frame-not-live"
            )
        )

        #expect(result.exitCode == 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        #expect(result.stdout.contains("mode-idle smoke skipped because startup frame is not live"))
        #expect(!result.stderr.contains("completed/skipped record missing"))
        #expect(!result.stderr.contains("skipped record missing"))
        #expect(!result.stderr.contains("did not complete successfully"))
    }

    @Test("review-journey verifier accepts one lossless correlated sidecar drain pair")
    func reviewJourneyVerifierAcceptsLosslessCorrelatedSidecarDrainPair() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = try writeStateFile(
            fixture: fixture,
            action: "bridge-review-observability-smoke"
        )

        let result = try fixture.runVerifier(
            scriptPath: "scripts/verify-bridge-review-journey-smoke.sh",
            stateFile: stateFile,
            environment: try reviewJourneyTelemetryEnvironment(fixture: fixture)
        )

        #expect(result.exitCode == 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        #expect(result.stdout.contains("one nonterminal telemetry sidecar drain receipt"))
        #expect(result.stdout.contains("one terminal telemetry sidecar drain receipt"))
        #expect(result.stdout.contains("telemetry sidecar drain receipts share one session digest"))
    }

    @Test(
        "review-journey verifier rejects invalid sidecar drain proof",
        arguments: [
            ("missing_terminal", "terminal telemetry sidecar drain receipt missing"),
            ("digest_mismatch", "telemetry sidecar drain receipts share one session digest"),
            ("required_loss", "terminal required telemetry loss"),
            ("optional_loss", "terminal optional telemetry loss"),
            ("worker_gap", "terminal worker sequence gaps"),
            ("native_gap", "terminal native batch sequence gaps"),
            ("proof_ineligible", "terminal telemetry proof eligible"),
            ("lossy", "terminal telemetry lossless"),
            ("settlement_missing", "terminal producer settlement acknowledged"),
            ("nonterminal_sequence_missing", "nonterminal accepted batch sequence present"),
            ("terminal_sequence_missing", "terminal accepted batch sequence present"),
            ("sequence_regression", "terminal accepted batch sequence covers nonterminal drain"),
        ]
    )
    func reviewJourneyVerifierRejectsInvalidSidecarDrainProof(
        failureCase: String,
        expectedFailure: String
    ) throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = try writeStateFile(
            fixture: fixture,
            action: "bridge-review-observability-smoke"
        )
        var environment = try reviewJourneyTelemetryEnvironment(fixture: fixture)
        environment["TELEMETRY_FAILURE_CASE"] = failureCase

        let result = try fixture.runVerifier(
            scriptPath: "scripts/verify-bridge-review-journey-smoke.sh",
            stateFile: stateFile,
            environment: environment
        )

        #expect(result.exitCode != 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        #expect(
            result.stdout.contains(expectedFailure) || result.stderr.contains(expectedFailure),
            "stdout: \(result.stdout)\nstderr: \(result.stderr)"
        )
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

    private func writeStateFile(
        fixture: LauncherScriptFixture,
        action: String
    ) throws -> URL {
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=debug-marker
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION=\(action)
        AGENTSTUDIO_OBSERVABILITY_PID=\(getpid())
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)
        return stateFile
    }

    private func completedResponseAppearsBeforeSkippedResponse(in script: String) -> Bool {
        guard
            let completedIndex = script.range(of: #"diagnostic_completed_response="$("#)?.lowerBound,
            let skippedIndex = script.range(of: #"diagnostic_skipped_response="$("#)?.lowerBound
        else {
            return false
        }
        return completedIndex < skippedIndex
    }

    private func frameNotLiveSkipEnvironment(
        fixture: LauncherScriptFixture,
        action: String,
        curlName: String
    ) throws -> [String: String] {
        [
            "AGENTSTUDIO_OBSERVABILITY_ALLOW_COMPLETED_EXIT": "1",
            "AGENTSTUDIO_OBSERVABILITY_VERIFY_ATTEMPTS": "1",
            "AGENTSTUDIO_OBSERVABILITY_VERIFY_RETRY_DELAY_SECONDS": "0",
            "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                curlName,
                """
                #!/bin/bash
                args="$*"
                if [[ "$args" == *"app.did_finish_launching.succeeded"* ]]; then
                  printf '{"_msg":"app.did_finish_launching.succeeded","agentstudio.app.startup.phase":"did_finish_launching","agentstudio.app.startup.outcome":"succeeded"}\\n'
                  exit 0
                fi
                if [[ "$args" == *"app.startup_diagnostic_action.command_exercised"* ]]; then
                  printf '{"_msg":"app.startup_diagnostic_action.command_exercised","agentstudio.startup_diagnostic.action":"\(action)","agentstudio.startup_diagnostic.render_proof.succeeded":false,"agentstudio.startup_diagnostic.bridge.frame_liveness.raf_alive":"false","agentstudio.startup_diagnostic.skip_reason":"frame_not_live"}\\n'
                  exit 0
                fi
                if [[ "$args" == *"app.startup_diagnostic_action.completed"* ]]; then
                  exit 0
                fi
                if [[ "$args" == *"app.startup_diagnostic_action.skipped"* ]]; then
                  printf '{"_msg":"app.startup_diagnostic_action.skipped","agentstudio.startup_diagnostic.action":"\(action)","agentstudio.startup_diagnostic.render_proof.succeeded":false,"agentstudio.startup_diagnostic.bridge.frame_liveness.raf_alive":"false","agentstudio.startup_diagnostic.skip_reason":"frame_not_live"}\\n'
                  exit 0
                fi
                if [[ "$args" == *":*"* ]]; then
                  exit 0
                fi
                printf '{"service.name":"AgentStudio","service.version":"0.0.1-debug+testcode","dev.runtime.flavor":"debug","_msg":"app.process.start"}\\n'
                exit 0
                """
            ).path,
        ]
    }

    private func reviewJourneyTelemetryEnvironment(
        fixture: LauncherScriptFixture
    ) throws -> [String: String] {
        [
            "AGENTSTUDIO_OBSERVABILITY_ALLOW_COMPLETED_EXIT": "1",
            "AGENTSTUDIO_OBSERVABILITY_VERIFY_ATTEMPTS": "1",
            "AGENTSTUDIO_OBSERVABILITY_VERIFY_RETRY_DELAY_SECONDS": "0",
            "AGENTSTUDIO_BRIDGE_REVIEW_JOURNEY_QUIESCENCE_SECONDS": "0",
            "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                "curl-review-journey-telemetry-sidecar",
                #"""
                #!/bin/bash
                args="$*"
                diagnostic='{"_msg":"app.startup_diagnostic_action.completed","agentstudio.startup_diagnostic.action":"bridge-review-observability-smoke","agentstudio.startup_diagnostic.bridge.review_expected_item.count":4,"agentstudio.startup_diagnostic.bridge.frame_liveness.raf_alive":"true","agentstudio.startup_diagnostic.bridge.frame_liveness.raf_fired_latency.bucket":"under_16ms","agentstudio.startup_diagnostic.bridge.bridge_command.count":1,"agentstudio.startup_diagnostic.bridge.review_intake_ready_command.count":1,"agentstudio.startup_diagnostic.bridge.bridge_response.count":1,"agentstudio.startup_diagnostic.bridge.intake_frame.count":1,"agentstudio.startup_diagnostic.bridge.review_intake_snapshot_frame.count":1,"agentstudio.startup_diagnostic.bridge.review_intake_metadata_window_frame.count":1,"agentstudio.startup_diagnostic.bridge.review_intake.last_frame_kind":"review.metadataWindow","agentstudio.startup_diagnostic.bridge.review_intake.last_stream_id_matches":true,"agentstudio.startup_diagnostic.bridge.page_issue.disallowed.count":0,"agentstudio.startup_diagnostic.render_proof.succeeded":true}'
                if [[ "$args" == *"app.did_finish_launching.succeeded"* ]]; then
                  printf '%s\n' '{"_msg":"app.did_finish_launching.succeeded","agentstudio.app.startup.phase":"did_finish_launching","agentstudio.app.startup.outcome":"succeeded"}'
                elif [[ "$args" == *"app.startup_diagnostic_action.command_exercised"* ]]; then
                  printf '%s\n' "${diagnostic/completed/command_exercised}"
                elif [[ "$args" == *"app.startup_diagnostic_action.completed"* ]]; then
                  printf '%s\n' "$diagnostic"
                elif [[ "$args" == *"performance.bridge.swift.telemetry_sidecar_drain"*"nonterminal_reopened"* ]]; then
                  nonterminal_accepted_field='"agentstudio.bridge.telemetry.accepted_batch.sequence":5,'
                  if [[ "${TELEMETRY_FAILURE_CASE:-}" == "nonterminal_sequence_missing" ]]; then nonterminal_accepted_field=""; fi
                  printf '{"_msg":"performance.bridge.swift.telemetry_sidecar_drain","agentstudio.bridge.phase":"nonterminal_reopened","agentstudio.bridge.telemetry.session.digest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",%s"agentstudio.bridge.telemetry.main_producer.high_watermark":8,"agentstudio.bridge.telemetry.comm_producer.high_watermark":7,"agentstudio.bridge.telemetry.required_loss.count":0,"agentstudio.bridge.telemetry.optional_loss.count":0,"agentstudio.bridge.telemetry.worker_sequence_gap.count":0,"agentstudio.bridge.telemetry.native_batch_sequence_gap.count":0,"agentstudio.bridge.telemetry.proof_eligible":true,"agentstudio.bridge.telemetry.lossy":false,"agentstudio.bridge.telemetry.settlement_acknowledged":true}\n' "$nonterminal_accepted_field"
                elif [[ "$args" == *"performance.bridge.swift.telemetry_sidecar_drain"*"terminal_closed"* ]]; then
                  if [[ "${TELEMETRY_FAILURE_CASE:-}" == "missing_terminal" ]]; then exit 0; fi
                  digest="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                  accepted=6
                  required=0
                  optional=0
                  worker_gap=0
                  native_gap=0
                  eligible=true
                  lossy=false
                  settled=true
                  case "${TELEMETRY_FAILURE_CASE:-}" in
                    digest_mismatch) digest="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" ;;
                    required_loss) required=1 ;;
                    optional_loss) optional=1 ;;
                    worker_gap) worker_gap=1 ;;
                    native_gap) native_gap=1 ;;
                    proof_ineligible) eligible=false ;;
                    lossy) lossy=true ;;
                    settlement_missing) settled=false ;;
                    sequence_regression) accepted=4 ;;
                  esac
                  terminal_accepted_field="\"agentstudio.bridge.telemetry.accepted_batch.sequence\":${accepted},"
                  if [[ "${TELEMETRY_FAILURE_CASE:-}" == "terminal_sequence_missing" ]]; then terminal_accepted_field=""; fi
                  printf '{"_msg":"performance.bridge.swift.telemetry_sidecar_drain","agentstudio.bridge.phase":"terminal_closed","agentstudio.bridge.telemetry.session.digest":"%s",%s"agentstudio.bridge.telemetry.main_producer.high_watermark":9,"agentstudio.bridge.telemetry.comm_producer.high_watermark":8,"agentstudio.bridge.telemetry.required_loss.count":%s,"agentstudio.bridge.telemetry.optional_loss.count":%s,"agentstudio.bridge.telemetry.worker_sequence_gap.count":%s,"agentstudio.bridge.telemetry.native_batch_sequence_gap.count":%s,"agentstudio.bridge.telemetry.proof_eligible":%s,"agentstudio.bridge.telemetry.lossy":%s,"agentstudio.bridge.telemetry.settlement_acknowledged":%s}\n' "$digest" "$terminal_accepted_field" "$required" "$optional" "$worker_gap" "$native_gap" "$eligible" "$lossy" "$settled"
                elif [[ "$args" == *"performance.bridge.web.selection_commit"* ]]; then
                  printf '%s\n%s\n%s\n%s\n' '{"_msg":"performance.bridge.web.selection_commit"}' '{"_msg":"performance.bridge.web.selection_commit"}' '{"_msg":"performance.bridge.web.selection_commit"}' '{"_msg":"performance.bridge.web.selection_commit"}'
                elif [[ "$args" == *"performance.bridge.web.code_view_item_materialize"* ]]; then
                  printf '%s\n%s\n%s\n' '{"_msg":"performance.bridge.web.code_view_item_materialize"}' '{"_msg":"performance.bridge.web.code_view_item_materialize"}' '{"_msg":"performance.bridge.web.code_view_item_materialize"}'
                elif [[ "$args" == *"performance.bridge.web.selected_content_painted"* ]]; then
                  printf '%s\n%s\n' '{"_msg":"performance.bridge.web.selected_content_painted","agentstudio.bridge.selected_content.materialize_ms":1}' '{"_msg":"performance.bridge.web.selected_content_painted","agentstudio.bridge.selected_content.materialize_ms":1}'
                elif [[ "$args" == *"performance.bridge.swift.content_load"* ]]; then
                  printf '%s\n%s\n%s\n%s\n' '{"_msg":"performance.bridge.swift.content_load"}' '{"_msg":"performance.bridge.swift.content_load"}' '{"_msg":"performance.bridge.swift.content_load"}' '{"_msg":"performance.bridge.swift.content_load"}'
                elif [[ "$args" == *"performance.bridge.web.selected_content_dropped"* ]] || [[ "$args" == *"performance.bridge.web.telemetry_drop"* ]] || [[ "$args" == *"app.startup_diagnostic_action.skipped"* ]]; then
                  exit 0
                elif [[ "$args" == *":*"* ]]; then
                  exit 0
                else
                  printf '%s\n' '{"service.name":"AgentStudio","service.version":"0.0.1-debug+testcode","dev.runtime.flavor":"debug","_msg":"app.process.start"}'
                fi
                """#
            ).path,
        ]
    }
}
