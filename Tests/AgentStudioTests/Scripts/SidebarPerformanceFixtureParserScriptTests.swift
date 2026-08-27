import AgentStudioInfrastructure
import Foundation
import Testing

@Suite("Sidebar performance fixture parser script")
struct SidebarPerformanceFixtureParserScriptTests {
    @Test("strict fixture parser accepts exact VictoriaLogs boolean strings")
    func strictFixtureParserAcceptsExactVictoriaLogsBooleanStrings() async throws {
        let prefix = "agentstudio.startup_diagnostic.sidebar_proof."
        let record = [
            prefix + "open_source_root_present": "true",
            prefix + "project_dev_root_present": "true",
            prefix + "control_root_present": "true",
            prefix + "discovered_repository_count": "121",
            prefix + "discovered_worktree_count": "147",
            prefix + "topology_fingerprint": String(repeating: "a", count: 64),
            prefix + "tab_count": "5",
            prefix + "pane_model_count": "20",
            prefix + "expected_session_variant": "0",
        ]
        let recordData = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        let recordJSON = try #require(String(data: recordData, encoding: .utf8))

        let accepted = try await runFixtureRecordContract(recordJSON)
        #expect(accepted.exitCode == 0, "stdout: \(accepted.stdout)\nstderr: \(accepted.stderr)")
        #expect(accepted.stdout.contains("STRICT_FIXTURE_REPOSITORY_COUNT=121"))
        #expect(accepted.stdout.contains("STRICT_FIXTURE_PANE_COUNT=20"))

        var rejectedRecord = record
        rejectedRecord[prefix + "open_source_root_present"] = "false"
        let rejectedData = try JSONSerialization.data(withJSONObject: rejectedRecord, options: [.sortedKeys])
        let rejectedJSON = try #require(String(data: rejectedData, encoding: .utf8))
        let rejected = try await runFixtureRecordContract(rejectedJSON)
        #expect(rejected.exitCode == 1)
        #expect(rejected.stderr.contains("strict fixture missing open-source root"))
    }

    private func runFixtureRecordContract(_ record: String) async throws -> ProcessResult {
        var environment = ProcessInfo.processInfo.environment
        environment["AGENTSTUDIO_OBSERVABILITY_ALLOW_TEST_OVERRIDES"] = "1"
        environment["AI_TOOLS_OBSERVABILITY_COLLECTOR_HEALTH_URL"] = "http://127.0.0.1:13133/"
        environment["AGENTSTUDIO_SIDEBAR_ALLOW_TEST_RESPONSES"] = "1"
        environment["AGENTSTUDIO_SIDEBAR_TEST_FIXTURE_RECORD"] = record
        environment["STRICT_POLICY_FIXTURE_TAB_COUNT"] = "5"
        environment["STRICT_POLICY_FIXTURE_PANE_MODEL_COUNT"] = "20"
        environment["STRICT_POLICY_ZERO_PTY_SESSION_COUNT"] = "0"
        environment["STRICT_POLICY_MOUNTED_PTY_SESSION_COUNT"] = "1"
        return try await DefaultProcessExecutor(timeout: 10).execute(
            command: "/bin/bash",
            args: ["scripts/verify-sidebar-performance-workload.sh", "--prepare-only"],
            cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            environment: environment
        )
    }
}
