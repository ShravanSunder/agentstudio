import Foundation
import Testing

@Suite("Observability debug verifier Bridge diagnostics")
struct ObservabilityDebugVerifierBridgeDiagnosticTests {
    @Test("debug observability verifier rejects Bridge Review proof without native lineage fields")
    func debugObservabilityVerifierRejectsBridgeReviewProofWithoutNativeLineageFields() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=debug-marker
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=testcode
        AGENTSTUDIO_OBSERVABILITY_PID=999999999
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION=bridge-review-observability-smoke
        AGENTSTUDIO_OBSERVABILITY_APP=\(shellEscapedStateValue(fixture.url("Agent Studio Debug testcode.app").path))
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)

        let result = try fixture.runVerifier(
            scriptPath: "scripts/verify-debug-observability.sh",
            stateFile: stateFile,
            environment: [
                "AGENTSTUDIO_OBSERVABILITY_ALLOW_COMPLETED_EXIT": "1",
                "AGENTSTUDIO_OBSERVABILITY_VERIFY_ATTEMPTS": "1",
                "AGENTSTUDIO_OBSERVABILITY_VERIFY_RETRY_DELAY_SECONDS": "0",
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "curl-review-diagnostic-without-native-lineage",
                    """
                    #!/bin/bash
                    if [[ "$*" == *"app.zmx_startup_reconciliation.completed"* ]]; then
                      printf '{"_msg":"app.zmx_startup_reconciliation.completed","agentstudio.zmx.startup.inventory_outcome":"complete","agentstudio.zmx.startup.live_session_count":1,"agentstudio.zmx.startup.hydrated_anchor_count":0,"agentstudio.zmx.startup.protected_session_count":1,"agentstudio.zmx.startup.unresolved_candidate_count":0,"agentstudio.zmx.startup.unmatched_live_session_count":0}\\n'
                      exit 0
                    fi
                    if [[ "$*" == *"app.startup_diagnostic_action.command_exercised"* ]] || [[ "$*" == *"app.startup_diagnostic_action.completed"* ]]; then
                      printf '{"_msg":"app.startup_diagnostic_action.completed","agentstudio.startup_diagnostic.action":"bridge-review-observability-smoke","agentstudio.startup_diagnostic.expected_visible_pane.count":1,"agentstudio.startup_diagnostic.render_proof.succeeded":true}\\n'
                      exit 0
                    fi
                    if [[ "$*" == *":*"* ]]; then
                      exit 0
                    fi
                    printf '{"service.name":"AgentStudio","service.version":"0.0.1-debug+testcode","dev.runtime.flavor":"debug","_msg":"app.process.start"}\\n'
                    exit 0
                    """
                ).path,
            ]
        )

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("Bridge Review diagnostic native lineage proof missing field"))
        #expect(result.stderr.contains("agentstudio.startup_diagnostic.bridge.bridge_command.count"))
    }

    @Test("debug observability verifier can allow completed Bridge diagnostic after process exit")
    func debugObservabilityVerifierAllowsCompletedBridgeDiagnosticAfterProcessExit() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=debug-marker
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=testcode
        AGENTSTUDIO_OBSERVABILITY_PID=999999999
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION=bridge-review-observability-smoke
        AGENTSTUDIO_OBSERVABILITY_APP=\(shellEscapedStateValue(fixture.url("Agent Studio Debug testcode.app").path))
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)
        let curlMarker = fixture.url("curl-called")
        let queryLog = fixture.url("curl-query.log")

        let result = try fixture.runVerifier(
            scriptPath: "scripts/verify-debug-observability.sh",
            stateFile: stateFile,
            environment: [
                "AGENTSTUDIO_OBSERVABILITY_ALLOW_COMPLETED_EXIT": "1",
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "curl",
                    """
                    #!/bin/bash
                    printf '%s\\n' "$*" >> "\(queryLog.path)"
                    echo called > "\(curlMarker.path)"
                    if [[ "$*" == *"app.zmx_startup_reconciliation.completed"* ]]; then
                      printf '{"_msg":"app.zmx_startup_reconciliation.completed","agentstudio.zmx.startup.inventory_outcome":"complete","agentstudio.zmx.startup.live_session_count":1,"agentstudio.zmx.startup.hydrated_anchor_count":0,"agentstudio.zmx.startup.protected_session_count":1,"agentstudio.zmx.startup.unresolved_candidate_count":0,"agentstudio.zmx.startup.unmatched_live_session_count":0}\\n'
                      exit 0
                    fi
                    if [[ "$*" == *"app.startup_diagnostic_action.command_exercised"* ]]; then
                      printf '{"_msg":"app.startup_diagnostic_action.command_exercised","agentstudio.startup_diagnostic.action":"bridge-review-observability-smoke","agentstudio.startup_diagnostic.expected_visible_pane.count":1,"agentstudio.startup_diagnostic.bridge.bridge_command.count":1,"agentstudio.startup_diagnostic.bridge.review_intake_ready_command.count":1,"agentstudio.startup_diagnostic.bridge.bridge_response.count":1,"agentstudio.startup_diagnostic.bridge.intake_frame.count":1,"agentstudio.startup_diagnostic.bridge.review_intake_snapshot_frame.count":1,"agentstudio.startup_diagnostic.bridge.review_intake_metadata_window_frame.count":1,"agentstudio.startup_diagnostic.bridge.review_intake.last_frame_kind":"review.metadataWindow","agentstudio.startup_diagnostic.bridge.review_intake.last_stream_id_matches":true,"agentstudio.startup_diagnostic.bridge.page_issue.disallowed.count":0,"agentstudio.startup_diagnostic.render_proof.succeeded":true}\\n'
                      exit 0
                    fi
                    if [[ "$*" == *"app.startup_diagnostic_action.completed"* ]]; then
                      printf '{"_msg":"app.startup_diagnostic_action.completed","agentstudio.startup_diagnostic.action":"bridge-review-observability-smoke","agentstudio.startup_diagnostic.expected_visible_pane.count":1,"agentstudio.startup_diagnostic.bridge.bridge_command.count":1,"agentstudio.startup_diagnostic.bridge.review_intake_ready_command.count":1,"agentstudio.startup_diagnostic.bridge.bridge_response.count":1,"agentstudio.startup_diagnostic.bridge.intake_frame.count":1,"agentstudio.startup_diagnostic.bridge.review_intake_snapshot_frame.count":1,"agentstudio.startup_diagnostic.bridge.review_intake_metadata_window_frame.count":1,"agentstudio.startup_diagnostic.bridge.review_intake.last_frame_kind":"review.metadataWindow","agentstudio.startup_diagnostic.bridge.review_intake.last_stream_id_matches":true,"agentstudio.startup_diagnostic.bridge.page_issue.disallowed.count":0,"agentstudio.startup_diagnostic.render_proof.succeeded":true}\\n'
                      exit 0
                    fi
                    if [[ "$*" == *":*"* ]]; then
                      exit 0
                    fi
                    printf '{"service.name":"AgentStudio","service.version":"0.0.1-debug+testcode","dev.runtime.flavor":"debug","_msg":"app.process.start"}\\n'
                    exit 0
                    """
                ).path,
            ]
        )

        #expect(result.exitCode == 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        #expect(FileManager.default.fileExists(atPath: curlMarker.path))
        let queries = try String(contentsOf: queryLog, encoding: .utf8)
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.review_expected_item.count"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.review_metadata_item.count"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.review_metadata_tree_row.count"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.review_metadata.converged"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.review_tree_click.selected_matches_target"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.modified_click.filter_requested"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.modified_click.click_attempt.count"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.modified_click.target_found"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.modified_click.first_rendered_present"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.modified_click.selected_matches_target"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.modified_click.rendered_row.count"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.modified_click.set_filter.status"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.selected_content.cache_keys_present"))
        #expect(
            queries.contains(
                "agentstudio.startup_diagnostic.bridge.modified_click.selected_content.cache_keys_present"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.review_shell.state"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.review_canvas.branch"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.review_shell.selected_content.state"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.selected_demand.failed.count"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.selected_demand.result.reason"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.modified_click.shell_selected_matches_target"))
    }

    @Test("debug observability verifier waits for Bridge diagnostic telemetry ingestion")
    func debugObservabilityVerifierWaitsForBridgeDiagnosticTelemetryIngestion() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=debug-marker
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=testcode
        AGENTSTUDIO_OBSERVABILITY_PID=999999999
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION=bridge-review-observability-smoke
        AGENTSTUDIO_OBSERVABILITY_APP=\(shellEscapedStateValue(fixture.url("Agent Studio Debug testcode.app").path))
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)
        let commandQueryCount = fixture.url("command-query-count")

        let result = try fixture.runVerifier(
            scriptPath: "scripts/verify-debug-observability.sh",
            stateFile: stateFile,
            environment: [
                "AGENTSTUDIO_OBSERVABILITY_ALLOW_COMPLETED_EXIT": "1",
                "AGENTSTUDIO_OBSERVABILITY_VERIFY_ATTEMPTS": "2",
                "AGENTSTUDIO_OBSERVABILITY_VERIFY_RETRY_DELAY_SECONDS": "0",
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "curl-delayed-bridge-diagnostic",
                    """
                    #!/bin/bash
                    if [[ "$*" == *"app.zmx_startup_reconciliation.completed"* ]]; then
                      printf '{"_msg":"app.zmx_startup_reconciliation.completed","agentstudio.zmx.startup.inventory_outcome":"complete","agentstudio.zmx.startup.live_session_count":1,"agentstudio.zmx.startup.hydrated_anchor_count":0,"agentstudio.zmx.startup.protected_session_count":1,"agentstudio.zmx.startup.unresolved_candidate_count":0,"agentstudio.zmx.startup.unmatched_live_session_count":0}\\n'
                      exit 0
                    fi
                    if [[ "$*" == *"app.startup_diagnostic_action.command_exercised"* ]]; then
                      count=0
                      if [ -f "\(commandQueryCount.path)" ]; then
                        count="$(cat "\(commandQueryCount.path)")"
                      fi
                      count=$((count + 1))
                      echo "$count" > "\(commandQueryCount.path)"
                      if [ "$count" -lt 2 ]; then
                        exit 0
                      fi
                      printf '{"_msg":"app.startup_diagnostic_action.command_exercised","agentstudio.startup_diagnostic.action":"bridge-review-observability-smoke","agentstudio.startup_diagnostic.expected_visible_pane.count":1,"agentstudio.startup_diagnostic.bridge.bridge_command.count":1,"agentstudio.startup_diagnostic.bridge.review_intake_ready_command.count":1,"agentstudio.startup_diagnostic.bridge.bridge_response.count":1,"agentstudio.startup_diagnostic.bridge.intake_frame.count":1,"agentstudio.startup_diagnostic.bridge.review_intake_snapshot_frame.count":1,"agentstudio.startup_diagnostic.bridge.review_intake_metadata_window_frame.count":1,"agentstudio.startup_diagnostic.bridge.review_intake.last_frame_kind":"review.metadataWindow","agentstudio.startup_diagnostic.bridge.review_intake.last_stream_id_matches":true,"agentstudio.startup_diagnostic.bridge.page_issue.disallowed.count":0,"agentstudio.startup_diagnostic.render_proof.succeeded":true}\\n'
                      exit 0
                    fi
                    if [[ "$*" == *"app.startup_diagnostic_action.completed"* ]]; then
                      printf '{"_msg":"app.startup_diagnostic_action.completed","agentstudio.startup_diagnostic.action":"bridge-review-observability-smoke","agentstudio.startup_diagnostic.expected_visible_pane.count":1,"agentstudio.startup_diagnostic.bridge.bridge_command.count":1,"agentstudio.startup_diagnostic.bridge.review_intake_ready_command.count":1,"agentstudio.startup_diagnostic.bridge.bridge_response.count":1,"agentstudio.startup_diagnostic.bridge.intake_frame.count":1,"agentstudio.startup_diagnostic.bridge.review_intake_snapshot_frame.count":1,"agentstudio.startup_diagnostic.bridge.review_intake_metadata_window_frame.count":1,"agentstudio.startup_diagnostic.bridge.review_intake.last_frame_kind":"review.metadataWindow","agentstudio.startup_diagnostic.bridge.review_intake.last_stream_id_matches":true,"agentstudio.startup_diagnostic.bridge.page_issue.disallowed.count":0,"agentstudio.startup_diagnostic.render_proof.succeeded":true}\\n'
                      exit 0
                    fi
                    if [[ "$*" == *":*"* ]]; then
                      exit 0
                    fi
                    printf '{"service.name":"AgentStudio","service.version":"0.0.1-debug+testcode","dev.runtime.flavor":"debug","_msg":"app.process.start"}\\n'
                    exit 0
                    """
                ).path,
            ]
        )

        #expect(result.exitCode == 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        let commandQueryValue = try String(contentsOf: commandQueryCount, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(commandQueryValue == "2")
    }

    @Test(
        "debug observability verifier accepts Bridge FileView diagnostic render proof",
        arguments: [
            "bridge-file-view-observability-smoke",
            "bridge-file-view-command-route-observability-smoke",
            "bridge-file-view-targeted-route-observability-smoke",
        ]
    )
    func debugObservabilityVerifierAcceptsBridgeFileViewDiagnosticRenderProof(
        diagnosticAction: String
    ) throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=debug-marker
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=testcode
        AGENTSTUDIO_OBSERVABILITY_PID=999999999
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION=\(diagnosticAction)
        AGENTSTUDIO_OBSERVABILITY_APP=\(shellEscapedStateValue(fixture.url("Agent Studio Debug testcode.app").path))
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)
        let queryLog = fixture.url("curl-query.log")

        let result = try fixture.runVerifier(
            scriptPath: "scripts/verify-debug-observability.sh",
            stateFile: stateFile,
            environment: [
                "AGENTSTUDIO_OBSERVABILITY_ALLOW_COMPLETED_EXIT": "1",
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "curl-file-view-diagnostic",
                    """
                    #!/bin/bash
                    printf '%s\\n' "$*" >> "\(queryLog.path)"
                    if [[ "$*" == *"app.zmx_startup_reconciliation.completed"* ]]; then
                      printf '{"_msg":"app.zmx_startup_reconciliation.completed","agentstudio.zmx.startup.inventory_outcome":"complete","agentstudio.zmx.startup.live_session_count":1,"agentstudio.zmx.startup.hydrated_anchor_count":0,"agentstudio.zmx.startup.protected_session_count":1,"agentstudio.zmx.startup.unresolved_candidate_count":0,"agentstudio.zmx.startup.unmatched_live_session_count":0}\\n'
                      exit 0
                    fi
                    if [[ "$*" == *"app.startup_diagnostic_action.command_exercised"* ]]; then
                      printf '{"_msg":"app.startup_diagnostic_action.command_exercised","agentstudio.startup_diagnostic.action":"\(diagnosticAction)","agentstudio.startup_diagnostic.expected_visible_pane.count":1,"agentstudio.startup_diagnostic.bridge.file_view.shell.visible":true,"agentstudio.startup_diagnostic.bridge.file_view.tree.visible":true,"agentstudio.startup_diagnostic.bridge.file_view.code_view.visible":true,"agentstudio.startup_diagnostic.bridge.file_view.bootstrap.protocol":"worktree-file","agentstudio.startup_diagnostic.bridge.file_view.bootstrap.source_spec.state":"parseable","agentstudio.startup_diagnostic.bridge.file_view.bootstrap.source_spec.length":512,"agentstudio.startup_diagnostic.bridge.file_view.descriptor.count":2,"agentstudio.startup_diagnostic.bridge.file_view.total_descriptor.count":2,"agentstudio.startup_diagnostic.bridge.file_view.source.state":"live","agentstudio.startup_diagnostic.bridge.file_view.open_file.state":"ready","agentstudio.startup_diagnostic.bridge.file_view.bridge_command.count":1,"agentstudio.startup_diagnostic.bridge.file_view.open_source_command.count":1,"agentstudio.startup_diagnostic.bridge.file_view.intake_ready_command.count":1,"agentstudio.startup_diagnostic.bridge.file_view.descriptor_request_command.count":1,"agentstudio.startup_diagnostic.bridge.file_view.bridge_response.count":1,"agentstudio.startup_diagnostic.bridge.file_view.intake_frame.count":1,"agentstudio.startup_diagnostic.bridge.file_view.native_probe.count":1,"agentstudio.startup_diagnostic.bridge.file_view.native_probe.last_stream_id_matches":true,"agentstudio.startup_diagnostic.bridge.worker_diagnostic.file_success_count":1,"agentstudio.startup_diagnostic.bridge.worker_diagnostic.failure_count":0,"agentstudio.startup_diagnostic.bridge.page_issue.disallowed.count":0,"agentstudio.startup_diagnostic.render_proof.succeeded":true}\\n'
                      exit 0
                    fi
                    if [[ "$*" == *"app.startup_diagnostic_action.completed"* ]]; then
                      printf '{"_msg":"app.startup_diagnostic_action.completed","agentstudio.startup_diagnostic.action":"\(diagnosticAction)","agentstudio.startup_diagnostic.expected_visible_pane.count":1,"agentstudio.startup_diagnostic.bridge.file_view.shell.visible":true,"agentstudio.startup_diagnostic.bridge.file_view.tree.visible":true,"agentstudio.startup_diagnostic.bridge.file_view.code_view.visible":true,"agentstudio.startup_diagnostic.bridge.file_view.bootstrap.protocol":"worktree-file","agentstudio.startup_diagnostic.bridge.file_view.bootstrap.source_spec.state":"parseable","agentstudio.startup_diagnostic.bridge.file_view.bootstrap.source_spec.length":512,"agentstudio.startup_diagnostic.bridge.file_view.descriptor.count":2,"agentstudio.startup_diagnostic.bridge.file_view.total_descriptor.count":2,"agentstudio.startup_diagnostic.bridge.file_view.source.state":"live","agentstudio.startup_diagnostic.bridge.file_view.open_file.state":"ready","agentstudio.startup_diagnostic.bridge.file_view.bridge_command.count":1,"agentstudio.startup_diagnostic.bridge.file_view.open_source_command.count":1,"agentstudio.startup_diagnostic.bridge.file_view.intake_ready_command.count":1,"agentstudio.startup_diagnostic.bridge.file_view.descriptor_request_command.count":1,"agentstudio.startup_diagnostic.bridge.file_view.bridge_response.count":1,"agentstudio.startup_diagnostic.bridge.file_view.intake_frame.count":1,"agentstudio.startup_diagnostic.bridge.file_view.native_probe.count":1,"agentstudio.startup_diagnostic.bridge.file_view.native_probe.last_stream_id_matches":true,"agentstudio.startup_diagnostic.bridge.worker_diagnostic.file_success_count":1,"agentstudio.startup_diagnostic.bridge.worker_diagnostic.failure_count":0,"agentstudio.startup_diagnostic.bridge.page_issue.disallowed.count":0,"agentstudio.startup_diagnostic.render_proof.succeeded":true}\\n'
                      exit 0
                    fi
                    if [[ "$*" == *"api/v1/query"* ]]; then
                      printf '{"status":"success","data":{"resultType":"vector","result":[{"metric":{},"value":[1780000000,"9"]}]}}\\n'
                      exit 0
                    fi
                    if [[ "$*" == *":*"* ]]; then
                      exit 0
                    fi
                    printf '{"service.name":"AgentStudio","service.version":"0.0.1-debug+testcode","dev.runtime.flavor":"debug","_msg":"app.process.start"}\\n'
                    exit 0
                    """
                ).path,
            ]
        )

        #expect(result.exitCode == 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        let queries = try String(contentsOf: queryLog, encoding: .utf8)
        #expect(queries.contains(diagnosticAction))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.file_view.tree.visible"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.file_view.expected_bootstrap.protocol"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.file_view.bootstrap.source_spec.state"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.file_view.open_file.state"))
        #expect(queries.contains("agentstudio.startup_diagnostic.bridge.worker_diagnostic.file_success_count"))
    }

    @Test("debug observability verifier requires Bridge FileView native metric percentiles")
    func debugObservabilityVerifierRequiresBridgeFileViewNativeMetricPercentiles() throws {
        let verifierScript = try String(
            contentsOfFile: "scripts/verify-debug-observability.sh",
            encoding: .utf8
        )

        #expect(verifierScript.contains("AI_TOOLS_OBSERVABILITY_METRICS_QUERY_URL"))
        #expect(verifierScript.contains("performance.bridge.native.metadata_open_to_first_window"))
        #expect(verifierScript.contains("performance.bridge.native.metadata_full_manifest_complete"))
        #expect(verifierScript.contains("histogram_quantile(0.95"))
        #expect(verifierScript.contains("histogram_quantile(0.99"))
        #expect(verifierScript.contains("agentstudio_performance_event_elapsed_ms_bucket"))
        #expect(verifierScript.contains("Bridge FileView native metric percentile proof"))
    }
}
