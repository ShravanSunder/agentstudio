import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@Suite("Performance report script")
struct PerformanceReportScriptTests {
    @Test("report resolves the latest completed candidate and preceding baseline")
    func resolvesCompletedWindows() async throws {
        let result = try await runReport(
            environment: [
                "AGENTSTUDIO_PERF_REPORT_LOGS_RESPONSE": fixtureRecords,
                "AGENTSTUDIO_PERF_REPORT_METRICS_RESPONSE": fixtureMetrics,
            ]
        )

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        #expect(result.stdout.contains("candidate: candidate-marker"))
        #expect(result.stdout.contains("baseline: baseline-marker"))
        #expect(result.stdout.contains("repo-explorer"))
        #expect(result.stdout.contains("p95"))
        #expect(result.stdout.contains("waste ratio"))
        #expect(result.stdout.contains("delta"))
        #expect(!result.stdout.contains("in-flight-marker"))
    }

    @Test("report resolves completed debug workload windows by runtime flavor")
    func resolvesCompletedDebugWorkloadWindows() async throws {
        let records = """
            [
              {"_time":"2026-08-10T10:00:00Z","_msg":"app.startup_diagnostic_action.completed","agent.proof.marker":"sidebar-baseline-marker","dev.release.channel":"stable","dev.runtime.flavor":"debug","agentstudio.startup_diagnostic.action":"sidebar-performance-proof"},
              {"_time":"2026-08-10T11:00:00Z","_msg":"app.startup_diagnostic_action.completed","agent.proof.marker":"title-pane-candidate-marker","dev.release.channel":"stable","dev.runtime.flavor":"debug","agentstudio.startup_diagnostic.action":"sidebar-performance-proof"}
            ]
            """
        let metrics = """
            {"sidebar-baseline-marker":[{"lane":"performance.terminal","p95":8.0,"waste_ratio":0.25}],"title-pane-candidate-marker":[{"lane":"performance.terminal","p95":6.0,"waste_ratio":0.10}]}
            """
        let result = try await runReport(
            arguments: ["--channel", "debug", "--lane", "performance.terminal"],
            environment: [
                "AGENTSTUDIO_PERF_REPORT_LOGS_RESPONSE": records,
                "AGENTSTUDIO_PERF_REPORT_METRICS_RESPONSE": metrics,
            ]
        )

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        #expect(result.stdout.contains("candidate: title-pane-candidate-marker"))
        #expect(result.stdout.contains("baseline: sidebar-baseline-marker"))
        #expect(result.stdout.contains("performance.terminal"))
    }

    @Test("report queries completion records before limiting high-volume workload logs")
    func queriesCompletionRecordsBeforeLimitingLogs() throws {
        let source = try String(contentsOfFile: "scripts/perf-report.sh", encoding: .utf8)

        #expect(source.contains("_msg:app.startup_diagnostic_action.completed | limit 10000"))
    }

    @Test("report names candidate selection failure with a distinct exit")
    func namesCandidateSelectionFailure() async throws {
        let result = try await runReport(
            arguments: ["--candidate", "missing-candidate"],
            environment: ["AGENTSTUDIO_PERF_REPORT_LOGS_RESPONSE": fixtureRecords]
        )

        #expect(result.exitCode == 4)
        #expect(result.stderr.contains("candidate selection failed: missing-candidate"))
    }

    @Test("report names baseline selection failure with a distinct exit")
    func namesBaselineSelectionFailure() async throws {
        let result = try await runReport(
            arguments: ["--baseline", "missing-baseline"],
            environment: ["AGENTSTUDIO_PERF_REPORT_LOGS_RESPONSE": fixtureRecords]
        )

        #expect(result.exitCode == 5)
        #expect(result.stderr.contains("baseline selection failed: missing-baseline"))
    }

    @Test("report names an unreachable endpoint with its own exit")
    func namesUnreachableEndpoint() async throws {
        let result = try await runReport(
            environment: [
                "AI_TOOLS_OBSERVABILITY_LOGS_QUERY_URL": "http://127.0.0.1:1/select/logsql/query"
            ]
        )

        #expect(result.exitCode == 3)
        #expect(result.stderr.contains("stack endpoint unreachable"))
        #expect(result.stderr.contains("127.0.0.1:1"))
    }

    @Test("script owns the reviewed completion resolver and mise task")
    func ownsCompletionResolverAndMiseTask() throws {
        let source = try String(contentsOfFile: "scripts/perf-report.sh", encoding: .utf8)
        let mise = try String(contentsOfFile: ".mise.toml", encoding: .utf8)

        #expect(source.contains("command-bar-repo-filter"))
        #expect(source.contains("sidebar-performance-proof"))
        #expect(source.contains("app.startup_diagnostic_action.completed"))
        #expect(source.contains("unknown runner families are in-flight"))
        #expect(mise.contains("[tasks.\"perf:report\"]"))
        #expect(mise.contains("scripts/perf-report.sh"))
    }

    private var fixtureRecords: String {
        """
        [
          {"_time":"2026-08-10T10:00:00Z","_msg":"app.startup_diagnostic_action.completed","agent.proof.marker":"baseline-marker","dev.release.channel":"stable","agentstudio.startup_diagnostic.action":"command-bar-repo-filter"},
          {"_time":"2026-08-10T11:00:00Z","_msg":"app.startup_diagnostic_action.completed","agent.proof.marker":"candidate-marker","dev.release.channel":"stable","agentstudio.startup_diagnostic.action":"sidebar-performance-proof"},
          {"_time":"2026-08-10T12:00:00Z","_msg":"performance.sidebar.projection","agent.proof.marker":"in-flight-marker","dev.release.channel":"stable","agentstudio.startup_diagnostic.action":"sidebar-performance-proof"}
        ]
        """
    }

    private var fixtureMetrics: String {
        """
        {"baseline-marker":[{"lane":"repo-explorer","p95":8.0,"waste_ratio":0.25}],"candidate-marker":[{"lane":"repo-explorer","p95":6.0,"waste_ratio":0.10}]}
        """
    }

    private func runReport(
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) async throws -> PerformanceReportResult {
        try await withoutBlockingCooperativePool {
            let stdoutURL = FileManager.default.temporaryDirectory
                .appending(path: "performance-report-stdout-\(UUIDv7.generate().uuidString).log")
            let stderrURL = FileManager.default.temporaryDirectory
                .appending(path: "performance-report-stderr-\(UUIDv7.generate().uuidString).log")
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
            process.arguments = ["scripts/perf-report.sh"] + arguments
            process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, newValue in newValue }
            process.standardOutput = stdoutHandle
            process.standardError = stderrHandle
            try process.run()
            process.waitUntilExit()
            try stdoutHandle.close()
            try stderrHandle.close()
            return PerformanceReportResult(
                exitCode: process.terminationStatus,
                stdout: try String(contentsOf: stdoutURL, encoding: .utf8),
                stderr: try String(contentsOf: stderrURL, encoding: .utf8)
            )
        }
    }
}

private struct PerformanceReportResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
