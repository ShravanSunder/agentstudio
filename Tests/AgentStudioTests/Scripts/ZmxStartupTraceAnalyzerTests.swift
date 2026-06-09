import Foundation
import Testing

@Suite(.serialized)
struct ZmxStartupTraceAnalyzerTests {
    @Test("analyzer summarizes successful startup trace with zmx log")
    func analyzerSummarizesSuccessfulStartupTraceWithZmxLog() throws {
        let paneID = UUID().uuidString
        let surfaceID = UUID().uuidString
        let operationID = UUID().uuidString
        let sessionID = "as-test-session"
        let fixture = try makeFixture(
            named: "zmx-startup-pass",
            lines: try appStartupFixtureLines() + [
                try traceRecord(
                    timeUnixNano: 1_000_000_000,
                    body: "terminal.startup.command_received",
                    attributes: [
                        "agentstudio.terminal.startup.phase": "command_received",
                        "agentstudio.terminal.startup.operation_id": operationID,
                    ]
                ),
                try traceRecord(
                    timeUnixNano: 1_001_000_000,
                    body: "terminal.startup.pane_created",
                    attributes: [
                        "agentstudio.pane.id": paneID,
                        "agentstudio.terminal.startup.phase": "pane_created",
                        "agentstudio.terminal.startup.operation_id": operationID,
                    ]
                ),
                try traceRecord(
                    timeUnixNano: 1_004_000_000,
                    body: "terminal.startup.zmx_attach_prepared",
                    attributes: [
                        "agentstudio.pane.id": paneID,
                        "agentstudio.terminal.startup.phase": "zmx_attach_prepared",
                        "agentstudio.terminal.startup.operation_id": operationID,
                        "agentstudio.zmx.session_id": sessionID,
                        "agentstudio.zmx.socket_path_headroom": 28,
                    ]
                ),
                try traceRecord(
                    timeUnixNano: 1_010_000_000,
                    body: "terminal.startup.surface_create_succeeded",
                    attributes: [
                        "agentstudio.pane.id": paneID,
                        "agentstudio.surface.id": surfaceID,
                        "agentstudio.terminal.startup.phase": "surface_create_succeeded",
                        "agentstudio.terminal.startup.operation_id": operationID,
                        "agentstudio.terminal.startup.outcome": "succeeded",
                    ]
                ),
                try traceRecord(
                    timeUnixNano: 1_030_000_000,
                    body: "terminal.startup.first_output",
                    attributes: [
                        "agentstudio.pane.id": paneID,
                        "agentstudio.surface.id": surfaceID,
                        "agentstudio.terminal.startup.phase": "first_output",
                    ]
                ),
            ]
        )
        let zmxLogDirectory = try makeZmxLogDirectory(
            named: "zmx-startup-pass-log",
            sessionID: sessionID,
            lines: [
                "[1000] [info] (main): creating session=\(sessionID)",
                "[1001] [info] (main): pty spawned session=\(sessionID) pid=123",
                "[1002] [info] (main): daemon started session=\(sessionID) pty_fd=9",
                "[1005] [info] (main): attached session=\(sessionID)",
                "[1006] [info] (main): client connected fd=10 total=1",
            ]
        )

        let result = try runAnalyzer([fixture.path, "--zmx-log", zmxLogDirectory.path])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("operation: \(operationID)"))
        #expect(result.stdout.contains("app startup timeline"))
        #expect(result.stdout.contains("app.ghostty_init.succeeded"))
        #expect(result.stdout.contains("workspace.boot.step"))
        #expect(result.stdout.contains("terminal.startup.command_received"))
        #expect(result.stdout.contains("terminal.startup.first_output"))
        #expect(result.stdout.contains("creating session=\(sessionID)"))
        #expect(result.stdout.contains("trace reached first output"))
    }

    @Test("analyzer identifies surface failure before zmx launch")
    func analyzerIdentifiesSurfaceFailureBeforeZmxLaunch() throws {
        let paneID = UUID().uuidString
        let operationID = UUID().uuidString
        let sessionID = "as-failed-before-zmx"
        let fixture = try makeFixture(
            named: "zmx-startup-surface-failed",
            lines: [
                try traceRecord(
                    timeUnixNano: 2_000_000_000,
                    body: "terminal.startup.command_received",
                    attributes: [
                        "agentstudio.terminal.startup.phase": "command_received",
                        "agentstudio.terminal.startup.operation_id": operationID,
                    ]
                ),
                try traceRecord(
                    timeUnixNano: 2_001_000_000,
                    body: "terminal.startup.pane_created",
                    attributes: [
                        "agentstudio.pane.id": paneID,
                        "agentstudio.terminal.startup.phase": "pane_created",
                        "agentstudio.terminal.startup.operation_id": operationID,
                    ]
                ),
                try traceRecord(
                    timeUnixNano: 2_003_000_000,
                    body: "terminal.startup.zmx_attach_prepared",
                    attributes: [
                        "agentstudio.pane.id": paneID,
                        "agentstudio.terminal.startup.phase": "zmx_attach_prepared",
                        "agentstudio.terminal.startup.operation_id": operationID,
                        "agentstudio.zmx.session_id": sessionID,
                        "agentstudio.zmx.socket_path_headroom": 28,
                    ]
                ),
                try traceRecord(
                    timeUnixNano: 2_004_000_000,
                    body: "terminal.startup.surface_create_started",
                    attributes: [
                        "agentstudio.pane.id": paneID,
                        "agentstudio.terminal.startup.phase": "surface_create_started",
                        "agentstudio.terminal.startup.operation_id": operationID,
                        "agentstudio.app.is_active": false,
                        "agentstudio.display.count": 2,
                    ]
                ),
                try traceRecord(
                    timeUnixNano: 2_025_000_000,
                    body: "terminal.startup.surface_create_failed",
                    attributes: [
                        "agentstudio.pane.id": paneID,
                        "agentstudio.terminal.startup.phase": "surface_create_failed",
                        "agentstudio.terminal.startup.operation_id": operationID,
                        "agentstudio.terminal.startup.outcome": "failed",
                        "agentstudio.terminal.startup.error": "Failed to create surface after 2 attempts",
                        "agentstudio.app.is_active": false,
                        "agentstudio.display.count": 2,
                    ]
                ),
            ]
        )
        let zmxLogDirectory = try makeZmxLogDirectory(
            named: "zmx-startup-empty-log",
            sessionID: sessionID,
            lines: []
        )

        let result = try runAnalyzer([fixture.path, "--zmx-log", zmxLogDirectory.path])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("app_active=false"))
        #expect(result.stdout.contains("no zmx events found for session \(sessionID)"))
        #expect(result.stdout.contains("surface creation failed before zmx emitted session events"))
    }

    @Test("analyzer treats child exit during startup as failed readiness")
    func analyzerTreatsChildExitDuringStartupAsFailedReadiness() throws {
        let paneID = UUID().uuidString
        let surfaceID = UUID().uuidString
        let operationID = UUID().uuidString
        let sessionID = "as-child-exited"
        let fixture = try makeFixture(
            named: "zmx-startup-child-exited",
            lines: [
                try traceRecord(
                    timeUnixNano: 3_000_000_000,
                    body: "terminal.startup.command_received",
                    attributes: [
                        "agentstudio.terminal.startup.phase": "command_received",
                        "agentstudio.terminal.startup.operation_id": operationID,
                    ]
                ),
                try traceRecord(
                    timeUnixNano: 3_001_000_000,
                    body: "terminal.startup.pane_created",
                    attributes: [
                        "agentstudio.pane.id": paneID,
                        "agentstudio.terminal.startup.phase": "pane_created",
                        "agentstudio.terminal.startup.operation_id": operationID,
                    ]
                ),
                try traceRecord(
                    timeUnixNano: 3_002_000_000,
                    body: "terminal.startup.zmx_attach_prepared",
                    attributes: [
                        "agentstudio.pane.id": paneID,
                        "agentstudio.terminal.startup.phase": "zmx_attach_prepared",
                        "agentstudio.terminal.startup.operation_id": operationID,
                        "agentstudio.zmx.session_id": sessionID,
                        "agentstudio.zmx.socket_path_headroom": -2,
                    ]
                ),
                try traceRecord(
                    timeUnixNano: 3_010_000_000,
                    body: "terminal.startup.surface_create_succeeded",
                    attributes: [
                        "agentstudio.pane.id": paneID,
                        "agentstudio.surface.id": surfaceID,
                        "agentstudio.terminal.startup.phase": "surface_create_succeeded",
                        "agentstudio.terminal.startup.operation_id": operationID,
                        "agentstudio.terminal.startup.outcome": "succeeded",
                    ]
                ),
                try traceRecord(
                    timeUnixNano: 3_020_000_000,
                    body: "terminal.startup.child_exited",
                    attributes: [
                        "agentstudio.pane.id": paneID,
                        "agentstudio.surface.id": surfaceID,
                        "agentstudio.terminal.startup.phase": "child_exited",
                        "agentstudio.terminal.startup.outcome": "failed",
                    ]
                ),
                try traceRecord(
                    timeUnixNano: 3_021_000_000,
                    body: "terminal.startup.first_output",
                    attributes: [
                        "agentstudio.pane.id": paneID,
                        "agentstudio.surface.id": surfaceID,
                        "agentstudio.terminal.startup.phase": "first_output",
                    ]
                ),
            ]
        )

        let result = try runAnalyzer([fixture.path])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("outcome: failed"))
        #expect(result.stdout.contains("socket_headroom=-2"))
        #expect(result.stdout.contains("terminal child exited during startup"))
    }

    @Test("analyzer reports missing startup records as contract failures")
    func analyzerReportsMissingStartupRecordsAsContractFailures() throws {
        let fixture = try makeFixture(named: "zmx-startup-missing-pane", lines: [])

        let result = try runAnalyzer([fixture.path])

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("missing terminal.startup.pane_created records"))
    }

    private func makeFixture(named name: String, lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(name)-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeZmxLogDirectory(named name: String, sessionID: String, lines: [String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let logURL = directory.appending(path: "\(sessionID).log")
        try lines.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
        return directory
    }

    private func appStartupFixtureLines() throws -> [String] {
        [
            try traceRecord(
                timeUnixNano: 900_000_000,
                body: "app.process.start",
                attributes: [
                    "agentstudio.app.startup.phase": "process"
                ]
            ),
            try traceRecord(
                timeUnixNano: 925_000_000,
                body: "app.ghostty_init.succeeded",
                attributes: [
                    "agentstudio.app.startup.phase": "ghostty_init",
                    "agentstudio.app.startup.outcome": "succeeded",
                ]
            ),
            try traceRecord(
                timeUnixNano: 975_000_000,
                body: "workspace.boot.step",
                attributes: [
                    "agentstudio.app.startup.phase": "workspace_boot",
                    "agentstudio.workspace.boot.step": "loadCanonicalStore",
                ]
            ),
        ]
    }

    private func traceRecord(
        timeUnixNano: UInt64,
        body: String,
        attributes: [String: Any]
    ) throws -> String {
        let record: [String: Any] = [
            "time_unix_nano": timeUnixNano,
            "body": body,
            "attributes": attributes,
        ]
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        guard let encodedRecord = String(bytes: data, encoding: .utf8) else {
            throw AnalyzerTestError.invalidUTF8Record
        }
        return encodedRecord
    }

    private func runAnalyzer(_ arguments: [String]) throws -> AnalyzerResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bash", "scripts/analyze-zmx-startup-trace.sh"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return AnalyzerResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}

private struct AnalyzerResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private enum AnalyzerTestError: Error {
    case invalidUTF8Record
}
