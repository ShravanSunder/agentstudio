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
            prefix + "warm_repository_count": "1",
            prefix + "inactive_repository_count": "119",
            prefix + "unknown_repository_count": "1",
            prefix + "warm_worktree_count": "1",
            prefix + "inactive_worktree_count": "145",
            prefix + "unknown_worktree_count": "1",
            prefix + "cold_automatic_deadline_count": "0",
            prefix + "cold_local_automatic_source_start_count": "0",
            prefix + "cold_fsevent_local_completion_count": "1",
            prefix + "explicit_source_admitted_count": "1",
            prefix + "explicit_source_terminal_count": "3",
            prefix + "explicit_progress_settled_count": "1",
            prefix + "explicit_local_admitted_count": "1",
            prefix + "explicit_remote_admitted_count": "0",
            prefix + "explicit_forge_admitted_count": "0",
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
        #expect(accepted.stdout.contains("STRICT_FIXTURE_WARM_REPOSITORY_COUNT=1"))
        #expect(accepted.stdout.contains("STRICT_FIXTURE_INACTIVE_REPOSITORY_COUNT=119"))
        #expect(accepted.stdout.contains("STRICT_FIXTURE_UNKNOWN_REPOSITORY_COUNT=1"))
        #expect(accepted.stdout.contains("STRICT_FIXTURE_UNKNOWN_WORKTREE_COUNT=1"))

        var missingUnknownRecord = record
        missingUnknownRecord[prefix + "unknown_repository_count"] = "0"
        missingUnknownRecord[prefix + "unknown_worktree_count"] = "0"
        let missingUnknownData = try JSONSerialization.data(
            withJSONObject: missingUnknownRecord,
            options: [.sortedKeys]
        )
        let missingUnknownJSON = try #require(
            String(data: missingUnknownData, encoding: .utf8)
        )
        let missingUnknown = try await runFixtureRecordContract(missingUnknownJSON)
        #expect(missingUnknown.exitCode == 1)
        #expect(missingUnknown.stderr.contains("strict fixture requires positive unknown membership"))

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
        return try await DefaultProcessExecutor(timeout: 10).execute(
            command: "/bin/bash",
            args: ["scripts/verify-sidebar-performance-workload.sh", "--prepare-only"],
            cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            environment: environment
        )
    }
}
