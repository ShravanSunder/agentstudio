import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct GitRefreshPerformanceWorkloadScriptTests {
    @Test("workload proof script has stable safety contract and bash syntax")
    func workloadProofScriptHasStableSafetyContractAndBashSyntax() throws {
        let syntax = try runScript(arguments: ["-n", scriptPath])
        let comparisonSyntax = try runScript(arguments: ["-n", comparisonScriptPath])
        let comparisonPythonSyntax = try runScript(arguments: [
            "-c", "/usr/bin/python3 -m py_compile \(comparisonPythonScriptPath)",
        ])
        #expect(syntax.exitCode == 0)
        #expect(comparisonSyntax.exitCode == 0, Comment(rawValue: comparisonSyntax.stderr))
        #expect(comparisonPythonSyntax.exitCode == 0, Comment(rawValue: comparisonPythonSyntax.stderr))

        let source = try String(contentsOf: URL(fileURLWithPath: scriptPath), encoding: .utf8)
        Self.expectSharedObservabilityContract(source)
        Self.expectDebugRunnerContract(source)
        Self.expectVictoriaProofContract(source)
        Self.expectJSONLProofGuard(source)
        Self.expectFixtureAndCleanupContract(source)
    }

    private static func expectSharedObservabilityContract(_ source: String) {
        #expect(source.contains("standard per-worktree debug observability"))
        #expect(source.contains("VictoriaMetrics performance evidence"))
        #expect(source.contains("LOGS_QUERY_URL="))
        #expect(source.contains("METRICS_QUERY_URL="))
        #expect(source.contains("AI_TOOLS_OBSERVABILITY_STACK_HELPER"))
        #expect(source.contains("$HOME/dev/ai-tools/observability/observability-stack"))
        #expect(!source.contains("SHRAVAN_OBSERVABILITY"))
        #expect(!source.contains("$HOME/dev/devfiles/shared/observability/observability-stack"))
        #expect(source.contains("Set >=255 when this script is used to cover"))
        #expect(source.contains("AGENTSTUDIO_PERF_DRIVE_COMMAND_BAR"))
        #expect(source.contains("AGENTSTUDIO_PERF_SAMPLE_DURING_WORKLOAD"))
        #expect(source.contains("Default: 0 so sampling cannot perturb"))
        #expect(source.contains("AGENTSTUDIO_PERF_ALLOW_JSONL_PROOF"))
        #expect(source.contains("AGENTSTUDIO_PERF_ALLOW_TEST_RESPONSES"))
        #expect(source.contains("standard proof requires Victoria"))
        #expect(source.contains("AGENTSTUDIO_OBSERVABILITY_STATE_FILE"))
        #expect(source.contains("DEFAULT_UI_PROOF_ROOT=\"/tmp/asperf\""))
        #expect(source.contains("absolute_path()"))
        #expect(source.contains("PROOF_ROOT=\"$(absolute_path \"$AGENTSTUDIO_PERF_PROOF_ROOT\")\""))
        #expect(source.contains("validate_trace_name()"))
        #expect(source.contains("safe path component"))
        #expect(source.contains("elif [ \"$DRIVE_COMMAND_BAR\" = \"1\" ]; then"))
        #expect(source.contains("TRACE_NAME=\"$(validate_trace_name \"perf-$(date +%H%M%S)-$$\")\""))
    }

    private static func expectDebugRunnerContract(_ source: String) {
        #expect(source.contains("load_debug_identity_for_workload()"))
        #expect(source.contains("\"$PROJECT_ROOT/scripts/run-debug-observability.sh\" --print-identity"))
        #expect(source.contains("APP_DATA_DIR=\"$(decode_env_file_value"))
        #expect(source.contains("TRACE_DIR=\"$APP_DATA_DIR/traces\""))
        #expect(source.contains("launch_debug_observability_app()"))
        #expect(source.contains("\"$PROJECT_ROOT/scripts/run-debug-observability.sh\" --detach"))
        #expect(source.contains("\"$PROJECT_ROOT/scripts/verify-debug-observability.sh\""))
        #expect(
            source.contains(
                "WORKLOAD_TRACE_TAGS=\"${AGENTSTUDIO_TRACE_TAGS:-performance,app.startup,terminal.startup}\""))
        #expect(source.contains("AGENTSTUDIO_TRACE_TAGS=$WORKLOAD_TRACE_TAGS"))
        #expect(source.contains("AGENTSTUDIO_TRACE_NAME=$TRACE_NAME"))
        #expect(source.contains("AGENTSTUDIO_TRACE_DIR=$TRACE_DIR"))
        #expect(source.contains("AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=command-bar-repo-filter"))
        #expect(source.contains("APP_PID=\"$(decode_env_file_value"))
        #expect(source.contains("DEBUG_STATE_COPY=\"$ARTIFACT/debug-observability.env\""))
        #expect(source.contains("cp \"$DEBUG_OBSERVABILITY_STATE_FILE\" \"$DEBUG_STATE_COPY\""))
        assertVictoriaMetricsContract(source)
        #expect(source.contains("preflight_debug_observability_idle()"))
        #expect(source.contains("\"$PROJECT_ROOT/scripts/run-debug-observability.sh\" --preflight-idle"))
        #expect(source.contains("QUERY_START=\"$(decode_env_file_value"))
        #expect(source.contains("--data-urlencode \"start=$QUERY_START\""))
        #expect(source.contains("SAMPLE_DURING_WORKLOAD=\"${AGENTSTUDIO_PERF_SAMPLE_DURING_WORKLOAD:-0}\""))
        #expect(source.contains("sample_during_workload=$SAMPLE_DURING_WORKLOAD"))
        #expect(source.contains("[ \"$SAMPLE_DURING_WORKLOAD\" = \"1\" ]"))
        #expect(source.contains("sample skipped during measured workload"))
        assertGitStatusMetricSummaryContract(source)
        #expect(source.contains("capture_restore_trace"))
        #expect(source.contains("grep \"pid=$APP_PID \" \"$restore_trace_source\""))
        #expect(
            source.contains("did not observe performance.coordinator.write within startup timeout\" >&2\n  sample_app"))
        #expect(source.contains("startup diagnostic command-bar repo filter smoke for PID"))
        #expect(source.contains("driver=startup-diagnostic"))
        #expect(source.contains("action=command-bar-repo-filter"))
        #expect(source.contains("startup command-bar repo filter smoke"))
        #expect(source.contains("wait_for_command_bar_repo_filter_event"))
        #expect(source.contains("agentstudio.performance.commandbar.query_character.count\\\":\\\"?[1-9][0-9]*\\\"?"))
    }

    private static func expectVictoriaProofContract(_ source: String) {
        #expect(source.contains("query_victoria_logs()"))
        #expect(source.contains("query_victoria_metrics()"))
        #expect(source.contains("logsql_escape_exact_value()"))
        #expect(source.contains("logsql_exact_filter()"))
        #expect(source.contains("victoria_event_query()"))
        #expect(
            source.contains(
                "printf '{service.name=\"AgentStudio\",dev.runtime.flavor=\"debug\"} %s %s'"
            ))
        #expect(
            source.contains("$(logsql_exact_filter \"agent.proof.marker\" \"$TRACE_NAME\")")
        )
        #expect(source.contains("$(logsql_exact_filter \"_msg\" \"$event_name\")"))
        #expect(!source.contains("agent.proof.marker:%s"))
        #expect(!source.contains("_msg:%s"))
        #expect(source.contains("victoria_event_count()"))
        #expect(source.contains("victoria_metric_event_query()"))
        #expect(source.contains("victoria_metric_event_count()"))
        #expect(source.contains("agentstudio_performance_events_total"))
        #expect(source.contains("agent.proof.marker=\"%s\",event=\"%s\""))
        #expect(source.contains("agentstudio_performance_event_elapsed_ms_bucket"))
        #expect(source.contains("histogram_quantile(0.95"))
        #expect(source.contains("victoria_event_elapsed_max()"))
        #expect(source.contains("victoria_metric_command_bar_filter_query()"))
        #expect(source.contains("agentstudio_performance_commandbar_query_character_count"))
        #expect(source.contains("performance.coordinator.write \\"))
        #expect(
            source.contains(
                "echo \"$event_name victoria_metrics_count=$victoria_metrics_count victoria_logs_count=$victoria_logs_count jsonl_count=$jsonl_count\""
            ))
        #expect(source.contains("allow_jsonl_proof=$ALLOW_JSONL_PROOF"))
        #expect(source.contains("performance.commandbar.filter.query_character.max="))
    }

    private static func expectJSONLProofGuard(_ source: String) {
        #expect(source.contains("jsonl_proof_enabled()"))
        #expect(source.contains("current_trace_jsonl_files()"))
        #expect(source.contains("find \"$TRACE_DIR\" -maxdepth 1 -name \"agentstudio-$TRACE_NAME-*.jsonl\""))
        #expect(source.contains("fail_if_trace_marker_would_reuse_jsonl()"))
        #expect(source.contains("trace marker already has JSONL files"))
        #expect(source.contains("jsonl_proof_enabled && current_trace_jsonl_has_event \"$event_name\""))
        #expect(source.contains("jsonl_proof_enabled && current_trace_jsonl_has_command_bar_filter"))
        #expect(!source.contains("if current_trace_jsonl_has_event \"$event_name\"; then"))
        #expect(!source.contains("if current_trace_jsonl_has_command_bar_filter; then"))
        #expect(!source.contains("grep -R \"\\\"body\\\":\\\"$event_name\\\"\" \"$TRACE_DIR\""))
        #expect(!source.contains("grep -R \"\\\"body\\\":\\\"performance.commandbar.filter\\\"\" \"$TRACE_DIR\""))
    }

    private static func expectFixtureAndCleanupContract(_ source: String) {
        #expect(!source.contains("AGENTSTUDIO_PERF_APP_BINARY"))
        #expect(!source.contains("AGENTSTUDIO_PERF_APP_BUNDLE"))
        #expect(!source.contains("AGENTSTUDIO_PERF_SKIP_BUILD"))
        #expect(!source.contains("AGENTSTUDIO_PERF_TRACE_BACKEND"))
        #expect(!source.contains("AgentStudio Performance Proof.app"))
        #expect(!source.contains("materialize_app_bundle_for_ui_smoke"))
        #expect(!source.contains("AGENTSTUDIO_DATA_DIR=\"$APP_DATA_DIR\""))
        #expect(!source.contains("mise run build"))
        #expect(!source.contains("ps -axo pid=,command="))
        #expect(!source.contains("pgrep -f \"$app_binary\""))
        #expect(source.contains("osascript") == false)
        #expect(source.contains("key code 35") == false)
        #expect(source.contains("cmd-P smoke") == false)
        #expect(source.contains("performance.commandbar.filter"))
        #expect(source.contains("git init \"$repo_dir\""))
        #expect(source.contains("git -C \"$repo_dir\" config user.email"))
        #expect(source.contains("mkdir -p \"$(dirname \"$worktree_dir\")\""))
        #expect(source.contains("commit.gpgsign false"))
        #expect(source.contains("tag.gpgsign false"))
        #expect(source.contains("stop_pid \"$APP_PID\""))
        #expect(source.contains("pkill") == false)
        #expect(source.contains("AGENTSTUDIO_PERF_ACTIVE_PANES"))
    }

    @Test("prepare-only summary emits comparable Victoria metric fields")
    func prepareOnlySummaryEmitsComparableVictoriaMetricFields() throws {
        let proofRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-workload-summary-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: proofRoot)
        }

        let result = try runScript(
            arguments: [scriptPath, "--prepare-only"],
            environment: [
                "AGENTSTUDIO_PERF_PROOF_ROOT": proofRoot.path,
                "AGENTSTUDIO_TRACE_NAME": "summary-shape-test",
                "AGENTSTUDIO_PERF_REPO_COUNT": "1",
                "AGENTSTUDIO_PERF_WORKTREE_COUNT": "1",
                "AGENTSTUDIO_PERF_ACTIVE_PANES": "1",
                "AGENTSTUDIO_PERF_WRITER_COUNT": "1",
                "AGENTSTUDIO_PERF_DURATION_SECONDS": "1",
                "AGENTSTUDIO_PERF_DRIVE_COMMAND_BAR": "0",
                "AGENTSTUDIO_PERF_ALLOW_TEST_RESPONSES": "1",
                "AI_TOOLS_OBSERVABILITY_LOGS_QUERY_URL": "http://127.0.0.1:1/select/logsql/query",
                "AI_TOOLS_OBSERVABILITY_METRICS_QUERY_URL": "http://127.0.0.1:1/api/v1/query",
                "AGENTSTUDIO_PERF_TEST_METRICS_RESPONSE":
                    #"{"status":"success","data":{"result":[{"value":[0,"7"]}]}}"#,
                "AGENTSTUDIO_PERF_TEST_LOGS_RESPONSE":
                    #"{"agentstudio.performance.elapsed_ms":"3"}"# + "\n"
                    + #"{"agentstudio.performance.elapsed_ms":"7"}"# + "\n",
            ]
        )

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))

        let summaryURL =
            proofRoot
            .appendingPathComponent("summary-shape-test")
            .appendingPathComponent("summary.txt")
        let summary = try String(contentsOf: summaryURL, encoding: .utf8)
        for eventName in Self.comparablePerformanceEventNames {
            #expect(summary.contains("\(eventName).victoria_metrics_count=7"))
            #expect(summary.contains("\(eventName).victoria_logs_count=2"))
            #expect(summary.contains("\(eventName).elapsed_ms.max=7"))
            #expect(summary.contains("\(eventName).elapsed_ms.p95=7"))
            #expect(summary.contains("\(eventName).elapsed_ms.p95_unavailable=false"))
        }
        #expect(summary.contains("performance.commandbar.filter.query_character.max=7"))
    }

    @Test("workload proof rejects canned query responses outside prepare-only tests")
    func workloadProofRejectsCannedQueryResponsesOutsidePrepareOnlyTests() throws {
        let proofRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-workload-test-response-guard-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: proofRoot)
        }

        let result = try runScript(
            arguments: [scriptPath],
            environment: [
                "AGENTSTUDIO_PERF_PROOF_ROOT": proofRoot.path,
                "AGENTSTUDIO_TRACE_NAME": "test-response-guard",
                "AGENTSTUDIO_PERF_REPO_COUNT": "1",
                "AGENTSTUDIO_PERF_WORKTREE_COUNT": "1",
                "AGENTSTUDIO_PERF_ACTIVE_PANES": "1",
                "AGENTSTUDIO_PERF_WRITER_COUNT": "1",
                "AGENTSTUDIO_PERF_DURATION_SECONDS": "1",
                "AI_TOOLS_OBSERVABILITY_COLLECTOR_HEALTH_URL": "http://127.0.0.1:1/",
                "AGENTSTUDIO_PERF_TEST_METRICS_RESPONSE":
                    #"{"status":"success","data":{"result":[{"value":[0,"7"]}]}}"#,
            ]
        )

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("AGENTSTUDIO_PERF_TEST_METRICS_RESPONSE"))
        #expect(result.stderr.contains("AGENTSTUDIO_PERF_ALLOW_TEST_RESPONSES"))
    }

    @Test("performance comparator fails when only coordinator write improves")
    func performanceComparatorFailsWhenOnlyCoordinatorWriteImproves() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let baselineWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10)
        )
        let afterWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 9)
                .merging([
                    "performance.coordinator.write.victoria_metrics_count": "1",
                    "performance.coordinator.write.elapsed_ms.p95": "1",
                    "performance.coordinator.write.elapsed_ms.max": "1",
                ]) { _, newValue in newValue }
        )
        let baselineInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-interaction.txt"),
            values: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1)
        )
        let afterInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-interaction.txt"),
            values: commandBarSummaryValues(itemsCount: 4, itemsP95: 10, itemsMax: 1)
        )
        let output = fixtureRoot.appendingPathComponent("comparison.txt")

        let result = try runScript(arguments: [
            comparisonScriptPath,
            "--baseline-workload", baselineWorkload.path,
            "--after-workload", afterWorkload.path,
            "--baseline-interaction", baselineInteraction.path,
            "--after-interaction", afterInteraction.path,
            "--output", output.path,
        ])

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("repo-cache fanout"))
        let comparison = try String(contentsOf: output, encoding: .utf8)
        #expect(comparison.contains("not_ready"))
    }

    @Test("performance comparator fails when coordinator write regresses")
    func performanceComparatorFailsWhenCoordinatorWriteRegresses() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let baselineWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10)
                .merging(coordinatorSummaryValues(count: 10, p95: 10, max: 10)) { _, newValue in newValue }
        )
        let afterWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 4, fanoutP95: 10, fanoutMax: 9)
                .merging(coordinatorSummaryValues(count: 12, p95: 10, max: 10)) { _, newValue in newValue }
        )
        let baselineInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-interaction.txt"),
            values: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1)
        )
        let afterInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-interaction.txt"),
            values: commandBarSummaryValues(itemsCount: 4, itemsP95: 10, itemsMax: 1)
        )
        let output = fixtureRoot.appendingPathComponent("comparison.txt")

        let result = try runScript(arguments: [
            comparisonScriptPath,
            "--baseline-workload", baselineWorkload.path,
            "--after-workload", afterWorkload.path,
            "--baseline-interaction", baselineInteraction.path,
            "--after-interaction", afterInteraction.path,
            "--output", output.path,
        ])

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("performance.coordinator.write.victoria_metrics_count regressed"))
        let comparison = try String(contentsOf: output, encoding: .utf8)
        #expect(comparison.contains("not_ready"))
    }

    @Test("performance comparator passes command-bar and repo-cache fanout thresholds")
    func performanceComparatorPassesCommandBarAndRepoCacheFanoutThresholds() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let baselineWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10)
        )
        let afterWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 4, fanoutP95: 10, fanoutMax: 9)
        )
        let baselineInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-interaction.txt"),
            values: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1)
        )
        let afterInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-interaction.txt"),
            values: commandBarSummaryValues(itemsCount: 4, itemsP95: 10, itemsMax: 1)
                .merging([
                    "performance.commandbar.filter.elapsed_ms.max": "100"
                ]) { _, newValue in newValue }
        )
        let output = fixtureRoot.appendingPathComponent("comparison.txt")

        let result = try runScript(arguments: [
            comparisonScriptPath,
            "--baseline-workload", baselineWorkload.path,
            "--after-workload", afterWorkload.path,
            "--baseline-interaction", baselineInteraction.path,
            "--after-interaction", afterInteraction.path,
            "--output", output.path,
        ])

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        let comparison = try String(contentsOf: output, encoding: .utf8)
        #expect(comparison.contains("ready"))
        #expect(comparison.contains("repo-cache fanout threshold met"))
        #expect(comparison.contains("performance.commandbar.filter.elapsed_ms.max is informational"))
    }

    @Test("performance comparator fails when required metrics are missing")
    func performanceComparatorFailsWhenRequiredMetricsAreMissing() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let baselineWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10)
        )
        let afterWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 4, fanoutP95: 10, fanoutMax: 9)
        )
        let baselineInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-interaction.txt"),
            values: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1)
        )
        var afterInteractionValues = commandBarSummaryValues(itemsCount: 4, itemsP95: 10, itemsMax: 1)
        afterInteractionValues.removeValue(forKey: "performance.commandbar.items.victoria_metrics_count")
        let afterInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-interaction.txt"),
            values: afterInteractionValues
        )
        let output = fixtureRoot.appendingPathComponent("comparison.txt")

        let result = try runScript(arguments: [
            comparisonScriptPath,
            "--baseline-workload", baselineWorkload.path,
            "--after-workload", afterWorkload.path,
            "--baseline-interaction", baselineInteraction.path,
            "--after-interaction", afterInteraction.path,
            "--output", output.path,
        ])

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("missing required metric"))
        let comparison = try String(contentsOf: output, encoding: .utf8)
        #expect(comparison.contains("not_ready"))
    }

    @Test("performance comparator fails when metrics disappear but logs remain")
    func performanceComparatorFailsWhenMetricsDisappearButLogsRemain() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let baselineWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10)
        )
        let afterWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 4, fanoutP95: 10, fanoutMax: 9)
        )
        let baselineInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-interaction.txt"),
            values: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1)
        )
        var afterInteractionValues = commandBarSummaryValues(itemsCount: 0, itemsP95: 10, itemsMax: 1)
        afterInteractionValues["performance.commandbar.items.victoria_logs_count"] = "10"
        let afterInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-interaction.txt"),
            values: afterInteractionValues
        )
        let output = fixtureRoot.appendingPathComponent("comparison.txt")

        let result = try runScript(arguments: [
            comparisonScriptPath,
            "--baseline-workload", baselineWorkload.path,
            "--after-workload", afterWorkload.path,
            "--baseline-interaction", baselineInteraction.path,
            "--after-interaction", afterInteraction.path,
            "--output", output.path,
        ])

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("instrumentation loss"))
        let comparison = try String(contentsOf: output, encoding: .utf8)
        #expect(comparison.contains("not_ready"))
    }

    @Test("performance comparator fails when command-bar interaction sequence differs")
    func performanceComparatorFailsWhenCommandBarInteractionSequenceDiffers() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let baselineWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10)
        )
        let afterWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 4, fanoutP95: 10, fanoutMax: 9)
        )
        let baselineInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-interaction.txt"),
            values: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1)
        )
        var afterInteractionValues = commandBarSummaryValues(itemsCount: 4, itemsP95: 10, itemsMax: 1)
        afterInteractionValues["performance.commandbar.filter.query_character.max"] = "1"
        let afterInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-interaction.txt"),
            values: afterInteractionValues
        )
        let output = fixtureRoot.appendingPathComponent("comparison.txt")

        let result = try runScript(arguments: [
            comparisonScriptPath,
            "--baseline-workload", baselineWorkload.path,
            "--after-workload", afterWorkload.path,
            "--baseline-interaction", baselineInteraction.path,
            "--after-interaction", afterInteraction.path,
            "--output", output.path,
        ])

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("command-bar interaction fingerprint changed"))
        let comparison = try String(contentsOf: output, encoding: .utf8)
        #expect(comparison.contains("not_ready"))
    }

    @Test("workload fixture JSON shape decodes as persisted workspace state")
    func workloadFixtureJSONShapeDecodesAsPersistedWorkspaceState() throws {
        let data = Data(workloadFixtureJSON.utf8)

        let state = try JSONDecoder().decode(WorkspacePersistor.PersistableState.self, from: data)

        #expect(state.repos.count == 1)
        #expect(state.worktrees.count == 1)
        #expect(state.panes.count == 1)
        #expect(state.tabs.count == 1)
        #expect(state.panes[0].worktreeId == state.worktrees[0].id)
    }

    private let scriptPath = "scripts/verify-git-refresh-performance-workload.sh"
    private let comparisonScriptPath = "scripts/compare-atomlib-v2-performance.sh"
    private let comparisonPythonScriptPath = "scripts/compare-atomlib-v2-performance.py"

    private static let comparablePerformanceEventNames = [
        "performance.commandbar.items",
        "performance.commandbar.filter",
        "performance.tabbar.refresh",
        "performance.sidebar.projection",
        "performance.sidebar.row_index",
        "performance.topology.repo_and_worktree",
        "performance.coordinator.write",
    ]

    private static func assertVictoriaMetricsContract(_ source: String) {
        #expect(source.contains("query_victoria_logs()"))
        #expect(source.contains("query_victoria_metrics()"))
        #expect(source.contains("victoria_event_query()"))
        #expect(source.contains("victoria_event_count()"))
        #expect(source.contains("victoria_metric_event_query()"))
        #expect(source.contains("victoria_metric_event_count()"))
        #expect(source.contains("victoria_metric_event_label_selector()"))
        #expect(source.contains("victoria_metric_event_count_for_reason()"))
        #expect(source.contains("victoria_metric_event_elapsed_p95()"))
        #expect(source.contains("victoria_metric_event_elapsed_max()"))
        #expect(source.contains("victoria_metric_status_unavailable_reason_values()"))
        #expect(source.contains("require_status_latency_metrics()"))
        #expect(source.contains("agentstudio_performance_events_total"))
        #expect(source.contains("agentstudio_performance_event_elapsed_ms_bucket"))
        #expect(source.contains("agentstudio_performance_event_elapsed_ms_max"))
        #expect(source.contains("agent.proof.marker=\"%s\",event=\"%s\""))
        #expect(source.contains("victoria_metric_command_bar_filter_query()"))
        #expect(source.contains("agentstudio_performance_commandbar_query_character_count"))
    }

    private static func assertGitStatusMetricSummaryContract(_ source: String) {
        #expect(source.contains("performance.git.status_unavailable\nperformance.git.snapshot_dedup"))
        #expect(source.contains("performance.git.status.elapsed_ms.p95="))
        #expect(source.contains("performance.git.status.elapsed_ms.max="))
        #expect(source.contains("performance.git.status_unavailable.reason.$unavailable_reason.count="))
        #expect(source.contains("performance.git.status_unavailable.reason.$unavailable_reason.elapsed_ms.p95="))
        #expect(source.contains("read_already_in_flight"))
    }

    private func runScript(
        arguments: [String],
        environment: [String: String] = [:]
    ) throws -> ScriptRunResult {
        let stdoutURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-script-stdout-\(UUID().uuidString).log")
        let stderrURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-script-stderr-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, newValue in newValue }
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        try process.run()
        process.waitUntilExit()
        try stdoutHandle.close()
        try stderrHandle.close()

        return ScriptRunResult(
            exitCode: process.terminationStatus,
            stdout: try String(contentsOf: stdoutURL, encoding: .utf8),
            stderr: try String(contentsOf: stderrURL, encoding: .utf8)
        )
    }

    private func temporaryFixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-performance-comparison-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeSummary(
        at url: URL,
        values: [String: String]
    ) throws -> URL {
        let body =
            values
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
        try (body + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func commandBarSummaryValues(
        itemsCount: Int,
        itemsP95: Int,
        itemsMax: Int
    ) -> [String: String] {
        [
            "performance.commandbar.items.victoria_metrics_count": "\(itemsCount)",
            "performance.commandbar.items.victoria_logs_count": "\(itemsCount)",
            "performance.commandbar.items.jsonl_count": "0",
            "performance.commandbar.items.elapsed_ms.p95": "\(itemsP95)",
            "performance.commandbar.items.elapsed_ms.p95_unavailable": "false",
            "performance.commandbar.items.elapsed_ms.max": "\(itemsMax)",
            "performance.commandbar.filter.victoria_metrics_count": "10",
            "performance.commandbar.filter.victoria_logs_count": "10",
            "performance.commandbar.filter.jsonl_count": "0",
            "performance.commandbar.filter.elapsed_ms.p95": "10",
            "performance.commandbar.filter.elapsed_ms.p95_unavailable": "false",
            "performance.commandbar.filter.elapsed_ms.max": "1",
            "performance.commandbar.filter.query_character.max": "10",
        ]
    }

    private func workloadSummaryValues(
        fanoutCount: Int,
        fanoutP95: Int,
        fanoutMax: Int
    ) -> [String: String] {
        var values: [String: String] = [:]
        for eventName in [
            "performance.tabbar.refresh",
            "performance.sidebar.projection",
            "performance.sidebar.row_index",
            "performance.topology.repo_and_worktree",
            "performance.coordinator.write",
        ] {
            values["\(eventName).victoria_metrics_count"] = "\(fanoutCount)"
            values["\(eventName).victoria_logs_count"] = "\(fanoutCount)"
            values["\(eventName).jsonl_count"] = "0"
            values["\(eventName).elapsed_ms.p95"] = "\(fanoutP95)"
            values["\(eventName).elapsed_ms.p95_unavailable"] = "false"
            values["\(eventName).elapsed_ms.max"] = "\(fanoutMax)"
        }
        return values
    }

    private func coordinatorSummaryValues(count: Int, p95: Int, max: Int) -> [String: String] {
        [
            "performance.coordinator.write.victoria_metrics_count": "\(count)",
            "performance.coordinator.write.victoria_logs_count": "\(count)",
            "performance.coordinator.write.jsonl_count": "0",
            "performance.coordinator.write.elapsed_ms.p95": "\(p95)",
            "performance.coordinator.write.elapsed_ms.p95_unavailable": "false",
            "performance.coordinator.write.elapsed_ms.max": "\(max)",
        ]
    }
}

private let workloadFixtureJSON = """
    {
      "schemaVersion": 1,
      "id": "00000000-0000-0000-0000-000000000101",
      "name": "Git Refresh Performance Fixture",
      "repos": [
        {
          "id": "00000000-0000-0000-0000-000000000201",
          "name": "repo-000",
          "repoPath": "file:///tmp/agentstudio-perf/repo-000",
          "createdAt": 0
        }
      ],
      "worktrees": [
        {
          "id": "00000000-0000-0000-0000-000000000301",
          "repoId": "00000000-0000-0000-0000-000000000201",
          "name": "main",
          "path": "file:///tmp/agentstudio-perf/repo-000",
          "isMainWorktree": true
        }
      ],
      "unavailableRepoIds": [],
      "panes": [
        {
          "id": "019eb9e5-2de8-7c5f-83b1-cc9782b2efb6",
          "content": {"version": 2, "type": "terminal", "state": {"provider": "zmx", "lifetime": "persistent"}},
          "metadata": {
            "paneId": "019eb9e5-2de8-7c5f-83b1-cc9782b2efb6",
            "contentType": {"terminal": {}},
            "source": {
              "worktree": {
                "worktreeId": "00000000-0000-0000-0000-000000000301",
                "repoId": "00000000-0000-0000-0000-000000000201",
                "launchDirectory": "file:///tmp/agentstudio-perf/repo-000"
              }
            },
            "executionBackend": {"local": {}},
            "createdAt": 0,
            "title": "repo-pane-0",
            "facets": {
              "repoId": "00000000-0000-0000-0000-000000000201",
              "worktreeId": "00000000-0000-0000-0000-000000000301",
              "cwd": "file:///tmp/agentstudio-perf/repo-000",
              "tags": []
            },
            "checkoutRef": null,
            "note": null
          },
          "residency": {"active": {}},
          "kind": {
            "layout": {
              "drawer": {
                "drawerId": "00000000-0000-0000-0000-000000000401",
                "parentPaneId": "019eb9e5-2de8-7c5f-83b1-cc9782b2efb6",
                "paneIds": [],
                "isExpanded": false
              }
            }
          }
        }
      ],
      "tabs": [
        {
          "id": "00000000-0000-0000-0000-000000000501",
          "name": "Performance",
          "panes": ["019eb9e5-2de8-7c5f-83b1-cc9782b2efb6"],
          "arrangements": [
            {
              "id": "00000000-0000-0000-0000-000000000601",
              "name": "Default",
              "isDefault": true,
              "layout": {
                "panes": [
                  {
                    "paneId": "019eb9e5-2de8-7c5f-83b1-cc9782b2efb6",
                    "ratio": 1.0
                  }
                ],
                "dividerIds": []
              },
              "minimizedPaneIds": [],
              "showsMinimizedPanes": true,
              "activePaneId": "019eb9e5-2de8-7c5f-83b1-cc9782b2efb6",
              "drawerViews": []
            }
          ],
          "activeArrangementId": "00000000-0000-0000-0000-000000000601"
        }
      ],
      "activeTabId": "00000000-0000-0000-0000-000000000501",
      "sidebarWidth": 250,
      "windowFrame": null,
      "watchedPaths": [],
      "createdAt": 0,
      "updatedAt": 0
    }
    """
