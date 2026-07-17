import Foundation
import Testing

@testable import AgentStudio

@Suite
struct SidebarPerformanceWorkloadScriptTests {
    @Test("sidebar workload proof script has stable safety contract and bash syntax")
    // swiftlint:disable:next function_body_length
    func sidebarWorkloadProofScriptHasStableSafetyContractAndBashSyntax() async throws {
        let syntax = try await runSidebarScript(arguments: ["-n", scriptPath])
        #expect(syntax.exitCode == 0, Comment(rawValue: syntax.stderr))

        let source = try String(contentsOfFile: scriptPath, encoding: .utf8)
        let miseConfig = try String(contentsOfFile: ".mise.toml", encoding: .utf8)

        #expect(source.contains("sidebar-performance-proof"))
        #expect(source.contains("TRACE_NONCE=\"$(/usr/bin/uuidgen)\""))
        #expect(source.contains("opaque_trace_marker \"$TRACE_NAME\" \"$TRACE_NONCE\""))
        #expect(source.contains("AGENTSTUDIO_IPC_UNSAFE_NO_AUTH"))
        #expect(source.contains("AGENTSTUDIO_OBSERVABILITY_ACTIVATION_MODE"))
        #expect(source.contains("AGENTSTUDIO_OBSERVABILITY_IPC_AUTH_MODE"))
        #expect(source.contains("performance.sidebar.projection"))
        #expect(source.contains("surface=~\"inbox|repo\""))
        #expect(
            source.contains(
                "phase=~\"startup_diagnostic|surface_switch|request_build_mainactor|mainactor_apply|projection_worker|row_index\""
            )
        )
        #expect(source.contains("surface=\"inbox\",phase=\"projection_worker\""))
        #expect(source.contains("surface=\"inbox\",phase=\"mainactor_apply\""))
        #expect(source.contains("agentstudio_performance_event_elapsed_ms_max"))
        #expect(source.contains("agentstudio_performance_event_elapsed_ms_bucket"))
        #expect(source.contains("histogram_quantile(0.95"))
        #expect(source.contains("trigger=\"%s\""))
        #expect(source.contains("grouping_switch"))
        #expect(!source.contains("\"sidebar.grouping.set\""))
        #expect(!source.contains("\"sidebar.surface.set\""))
        #expect(source.contains("\"setRepoSidebarGroupingRepo\""))
        #expect(source.contains("\"setRepoSidebarGroupingPane\""))
        #expect(source.contains("\"setRepoSidebarGroupingTab\""))
        #expect(source.contains("\"setInboxGroupingTab\""))
        #expect(source.contains("\"setInboxGroupingRepo\""))
        #expect(source.contains("\"setInboxGroupingPane\""))
        #expect(source.contains("\"setInboxGroupingNone\""))
        #expect(source.contains("\"showWorktreeSidebar\""))
        #expect(source.contains("\"showInboxNotifications\""))
        #expect(source.contains("\"setRepoSidebarVisibilityMode\""))
        #expect(source.contains("\"arguments\": {\"mode\": mode}"))
        #expect(source.contains("visibility_mode"))
        #expect(source.contains("\"setRepoSidebarSortOrder\""))
        #expect(source.contains("\"arguments\": {\"order\": order}"))
        #expect(source.contains("sort_order"))
        #expect(source.contains("repo_sort_projection_worker_elapsed_ms_p95"))
        #expect(source.contains("repo_sort_mainactor_apply_elapsed_ms_p95"))
        #expect(source.contains("repo_sort_request_build_mainactor_elapsed_ms_p95"))
        #expect(source.contains("repo_sort_row_index_elapsed_ms_p95"))
        #expect(source.contains("repo_visibility_projection_worker_elapsed_ms_p95"))
        #expect(source.contains("repo_visibility_mainactor_apply_elapsed_ms_p95"))
        #expect(source.contains("\"auth.login replay\""))
        #expect(source.contains("repo_pane_projection_worker_elapsed_ms_p95"))
        #expect(source.contains("repo_pane_projection_worker_elapsed_ms_count"))
        #expect(source.contains("for mode_name in repo pane tab"))
        #expect(source.contains("for phase in request_build_mainactor projection_worker row_index mainactor_apply"))
        #expect(source.contains("\"repo_${mode_name}_${phase}\""))
        #expect(source.contains("repo_pane_request_build_mainactor_elapsed_ms_p95"))
        #expect(source.contains("repo_pane_row_index_elapsed_ms_p95"))
        #expect(source.contains("repo_tab_mainactor_apply_elapsed_ms_max"))
        #expect(source.contains("for mode_name in tab repo pane none"))
        #expect(source.contains("for phase in request_build_mainactor projection_worker mainactor_apply"))
        #expect(source.contains("\"inbox_${mode_name}_${phase}\""))
        #expect(source.contains("inbox_none_projection_worker_elapsed_ms_p95"))
        #expect(source.contains("inbox_none_request_build_mainactor_elapsed_ms_p95"))
        #expect(source.contains("inbox_pane_mainactor_apply_elapsed_ms_max"))
        #expect(source.contains("surface_switch_repo_end_to_end_elapsed_ms_p95"))
        #expect(source.contains("surface_switch_inbox_end_to_end_elapsed_ms_p95"))
        #expect(source.contains("metric_event_elapsed_p95_query repo surface_switch not_applicable surface_switch"))
        #expect(!source.contains(". \"$BASELINE_FILE\""))
        #expect(source.contains("load_baseline_metric_value"))
        #expect(source.contains("record_required_sidebar_metric_matrix"))
        #expect(source.contains("compare_required_metric_matrix"))
        #expect(source.contains("required_metric_keys="))
        #expect(source.contains("wait_for_required_metric_count"))
        #expect(source.contains("REQUIRED_SAMPLE_COUNT=100"))
        #expect(source.contains("AGENTSTUDIO_SIDEBAR_IPC_CYCLES:-100"))
        #expect(source.contains("must be >= {minimum}"))
        #expect(source.contains("def wait_for_readback"))
        #expect(source.contains("time.monotonic() + timeout"))
        #expect(source.contains("readiness timed out"))
        #expect(!source.contains("sidebar grouping read-back mismatch"))
        #expect(!source.contains("sidebar surface read-back mismatch"))
        #expect(source.contains("workload_fixture_key=$WORKLOAD_FIXTURE_KEY"))
        #expect(source.contains("worktree_fixture_key=$WORKTREE_FIXTURE_KEY"))
        #expect(source.contains("sidebar baseline workload fixture mismatch"))
        #expect(source.contains("sidebar baseline worktree fixture mismatch"))
        #expect(source.contains("validate_compare_baseline_fixture"))
        #expect(source.contains("\"sidebar.grouping.get\""))
        #expect(source.contains("\"sidebar.surface.get\""))
        #expect(source.contains("sidebar_surface_switch.ipc_sequence=repo,inbox,repo,inbox,repo"))
        #expect(source.contains("repo_sort.ipc_sequence=descending,ascending"))
        #expect(source.contains("repo_visibility.ipc_sequence=favoritesOnly,all"))
        #expect(source.contains("sidebar-performance-baseline.env"))
        #expect(source.contains("performance_threshold_check"))
        #expect(source.contains("requires authenticated IPC auth mode"))
        #expect(source.contains("requires background LaunchServices activation mode"))
        #expect(!source.contains("notification_text"))
        #expect(!source.contains("query_text"))
        #expect(!source.contains("osascript"))
        #expect(miseConfig.contains("[tasks.verify-sidebar-performance-workload]"))
        #expect(
            miseConfig.contains(
                "run = \"/bin/bash scripts/verify-sidebar-performance-workload.sh --sidebar-proof\""
            )
        )
    }

    @Test("prepare-only emits comparable sidebar summary without launching app")
    func prepareOnlyEmitsComparableSidebarSummaryWithoutLaunchingApp() async throws {
        let proofRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-sidebar-workload-summary-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: proofRoot)
        }

        let result = try await runSidebarScript(
            arguments: [scriptPath, "--prepare-only"],
            environment: [
                "AGENTSTUDIO_SIDEBAR_PROOF_ROOT": proofRoot.path,
                "AGENTSTUDIO_TRACE_NAME": "sidebar-summary-shape-test",
                "AGENTSTUDIO_SIDEBAR_ALLOW_TEST_RESPONSES": "1",
                "AGENTSTUDIO_SIDEBAR_TEST_METRICS_RESPONSE":
                    #"{"status":"success","data":{"result":[{"value":[0,"1"]}]}}"#,
                "AI_TOOLS_OBSERVABILITY_METRICS_QUERY_URL": "http://127.0.0.1:1/api/v1/query",
            ]
        )

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        let summaryURL =
            proofRoot
            .appendingPathComponent("sidebar-summary-shape-test")
            .appendingPathComponent("summary.txt")
        let summary = try String(contentsOf: summaryURL, encoding: .utf8)
        #expect(summary.contains("mode=prepare-only"))
        #expect(summary.contains("startup_diagnostic=sidebar-performance-proof"))
        #expect(summary.contains("requires_unsafe_no_auth=false"))
        #expect(summary.contains("requires_non_foreground_activation=true"))
        #expect(summary.contains("workload_fixture_key="))
        #expect(summary.contains("worktree_fixture_key="))
        #expect(summary.contains("workload_cycles=100"))
        #expect(summary.contains("sidebar_projection.metric_result_count=1"))
    }

    @Test("workload rejects fewer than one hundred issued samples per bucket")
    func workloadRejectsFewerThanOneHundredIssuedSamplesPerBucket() async throws {
        let result = try await runSidebarScript(
            arguments: [scriptPath, "--prepare-only"],
            environment: ["AGENTSTUDIO_SIDEBAR_IPC_CYCLES": "99"]
        )

        #expect(result.exitCode == 2)
        #expect(result.stderr.contains("AGENTSTUDIO_SIDEBAR_IPC_CYCLES must be >= 100: 99"))
    }

    @Test("compare rejects mismatched fixture metadata before launch")
    func compareRejectsMismatchedFixtureMetadataBeforeLaunch() async throws {
        let proofRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-sidebar-baseline-mismatch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: proofRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: proofRoot)
        }
        try "workload_fixture_key=stale\nworktree_fixture_key=stale\n".write(
            to: proofRoot.appendingPathComponent("sidebar-performance-baseline.env"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await runSidebarScript(
            arguments: [scriptPath, "--compare"],
            environment: [
                "AGENTSTUDIO_SIDEBAR_PROOF_ROOT": proofRoot.path,
                "AGENTSTUDIO_TRACE_NAME": "sidebar-fixture-mismatch-test",
            ]
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("sidebar baseline workload fixture mismatch"))
    }

    @Test("proof modes reject unsafe no-auth IPC before launching")
    func proofModesRejectUnsafeNoAuthIPCBeforeLaunching() async throws {
        let proofRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-sidebar-unsafe-no-auth-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: proofRoot)
        }

        let result = try await runSidebarScript(
            arguments: [scriptPath, "--sidebar-proof"],
            environment: [
                "AGENTSTUDIO_SIDEBAR_PROOF_ROOT": proofRoot.path,
                "AGENTSTUDIO_TRACE_NAME": "sidebar-unsafe-no-auth-test",
                "AGENTSTUDIO_IPC_UNSAFE_NO_AUTH": "1",
            ]
        )

        #expect(result.exitCode == 2)
        #expect(result.stderr.contains("refuses AGENTSTUDIO_IPC_UNSAFE_NO_AUTH"))
    }

    private let scriptPath = "scripts/verify-sidebar-performance-workload.sh"
}

private func runSidebarScript(
    arguments: [String],
    environment: [String: String] = [:]
) async throws -> ProcessResult {
    var mergedEnvironment = ProcessInfo.processInfo.environment
    mergedEnvironment["AGENTSTUDIO_OBSERVABILITY_ALLOW_TEST_OVERRIDES"] = "1"
    mergedEnvironment["AI_TOOLS_OBSERVABILITY_COLLECTOR_HEALTH_URL"] = "http://127.0.0.1:13133/"
    for (key, value) in environment {
        mergedEnvironment[key] = value
    }
    return try await DefaultProcessExecutor(timeout: 10).execute(
        command: "/bin/bash",
        args: arguments,
        cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        environment: mergedEnvironment
    )
}
