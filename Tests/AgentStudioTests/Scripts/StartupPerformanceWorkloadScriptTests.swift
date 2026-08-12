import Foundation
import Testing

@Suite("Startup performance workload script")
struct StartupPerformanceWorkloadScriptTests {
    private let scriptPath = "scripts/verify-startup-performance-workload.sh"

    @Test("dry run exposes the fixed completion and trace contract")
    func dryRunExposesWorkloadContract() throws {
        let result = try runScript(arguments: ["--dry-run"])

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        #expect(result.stdout.contains("sample_count=10"))
        #expect(result.stdout.contains("trace_tags=performance,app.startup"))
        #expect(result.stdout.contains("trace_flush=immediate"))
        #expect(result.stdout.contains("startup_diagnostic=command-bar-repo-filter"))
        #expect(result.stdout.contains("completion=app.startup_diagnostic_action.completed"))
        #expect(result.stdout.contains("usable_lane=performance.startup.usable"))
        #expect(result.stdout.contains("renderer_probe=program_instrument_gap"))
    }

    @Test("sample count below ten is rejected with a distinct usage exit")
    func rejectsTooFewSamples() throws {
        let result = try runScript(
            arguments: ["--dry-run"],
            environment: ["AGENTSTUDIO_STARTUP_PERFORMANCE_SAMPLE_COUNT": "9"]
        )

        #expect(result.exitCode == 2)
        #expect(result.stderr.contains("must be an integer >= 10"))
    }

    @Test("script carries identity guarded reset and bounded completion wait")
    func ownsHardenedLifecycleContract() throws {
        let source = try String(contentsOfFile: scriptPath, encoding: .utf8)

        #expect(source.contains("run-debug-observability.sh\" --print-identity"))
        #expect(source.contains("refusing reset outside isolated debug roots"))
        #expect(source.contains("refusing reset for mismatched debug bundle identifier"))
        #expect(source.contains("AGENTSTUDIO_TRACE_FLUSH=immediate"))
        #expect(source.contains("AGENTSTUDIO_TRACE_TAGS=performance,app.startup"))
        #expect(source.contains("app.startup_diagnostic_action.completed"))
        #expect(source.contains("performance.startup.usable"))
        #expect(source.contains("seq 1 \"$COMPLETION_ATTEMPTS\""))
        #expect(!source.contains("AGENTSTUDIO_PERF_ALLOW_JSONL_PROOF"))
    }

    private func runScript(
        arguments: [String],
        environment: [String: String] = [:]
    ) throws -> ScriptResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, newValue in newValue }
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return ScriptResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}

private struct ScriptResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
