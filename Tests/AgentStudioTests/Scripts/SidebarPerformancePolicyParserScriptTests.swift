import Foundation
import Testing

@Suite
struct SidebarPerformancePolicyParserScriptTests {
    @Test("projected integral policy numbers are canonicalized for shell arithmetic")
    func projectedIntegralPolicyNumbersAreCanonicalizedForShellArithmetic() async throws {
        let prefix = "agentstudio.startup_diagnostic.sidebar_proof."
        let record: [String: Any] = [
            prefix + "policy_id": "strict-sidebar-cpu",
            prefix + "policy_version": 3,
            prefix + "idle_p99_max_percent": 10.0,
            prefix + "action_p95_max_percent": 20.0,
            prefix + "sample_interval_ms": 1000.0,
            prefix + "idle_sample_floor": 1000,
            prefix + "action_count_floor": 100,
            prefix + "action_sample_floor": 200,
            prefix + "fixture_preparation_timeout_ms": 300_000.0,
            prefix + "fixture_state_observation_interval_ms": 10.0,
            prefix + "fixture_tab_count": 5,
            prefix + "fixture_pane_model_count": 20,
            prefix + "zero_pty_expected_session_count": 0,
            prefix + "mounted_pty_expected_session_count": 1,
            prefix + "zmx_inventory_interval_ms": 5000.0,
            prefix + "quiescence_interval_ms": 5000.0,
            prefix + "readback_timeout_ms": 5000.0,
            prefix + "sampler_gap_max_ms": 1250.0,
            prefix + "unrelated_host_cpu_max_percent": 20.0,
            prefix + "diagnostic_cpu_delta_max_points": 5.0,
            prefix + "diagnostic_interaction_growth_max_percent": 10.0,
            prefix + "git_status_physical_limit": 4,
            prefix + "git_maximum_settlement_ms": 960_000.0,
            prefix + "standard_trace_tags": "performance,app.startup,terminal.startup",
            prefix + "diagnostic_trace_tags": "performance,atoms,app.startup,terminal.startup",
            prefix + "idle_populations": "zero_pty_idle,quiescent_pty_idle",
            prefix + "action_populations": "search_clear,grouping,hide_show,tab_switch",
        ]
        let recordData = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        var recordJSON = try #require(String(data: recordData, encoding: .utf8))
        for (field, value) in [
            ("sample_interval_ms", "1000"),
            ("fixture_preparation_timeout_ms", "300000"),
            ("git_maximum_settlement_ms", "960000"),
        ] {
            recordJSON = recordJSON.replacingOccurrences(
                of: "\(prefix)\(field)\":\(value)",
                with: "\(prefix)\(field)\":\(value).0"
            )
            #expect(recordJSON.contains("\(prefix)\(field)\":\(value).0"))
        }

        let result = try await runSidebarScript(
            arguments: ["scripts/verify-sidebar-performance-workload.sh", "--prepare-only"],
            environment: [
                "AGENTSTUDIO_SIDEBAR_ALLOW_TEST_RESPONSES": "1",
                "AGENTSTUDIO_SIDEBAR_TEST_POLICY_RECORD": recordJSON,
            ]
        )

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        #expect(result.stdout.contains("STRICT_POLICY_SAMPLE_INTERVAL_MS=1000\n"))
        #expect(result.stdout.contains("STRICT_POLICY_FIXTURE_PREPARATION_TIMEOUT_MS=300000\n"))
        #expect(result.stdout.contains("STRICT_POLICY_GIT_MAXIMUM_SETTLEMENT_MS=960000\n"))
    }
}
