import Foundation
import Testing

@Suite(.serialized)
struct NotificationOSCSmokeVerifierTests {
    @Test("verifier accepts a complete notification smoke fixture")
    func verifierAcceptsCompleteNotificationSmokeFixture() throws {
        let fixture = try makeFixture(
            named: "notification-smoke-pass",
            lines: [
                try traceRecord(
                    body: "terminal.activity.observed",
                    attributes: ["agentstudio.runtime.event": "terminal.desktopNotificationRequested"]
                ),
                try traceRecord(
                    body: "inbox.classify",
                    attributes: [
                        "agentstudio.runtime.event": "terminal.desktopNotificationRequested",
                        "agentstudio.inbox.decision": "notify",
                    ]
                ),
                try traceRecord(
                    body: "inbox.promote",
                    attributes: [
                        "agentstudio.inbox.kind": "agentDesktopNotification",
                        "agentstudio.inbox.decision": "promote",
                    ]
                ),
                try traceRecord(
                    body: "inbox.notification.appended",
                    attributes: ["agentstudio.inbox.kind": "agentDesktopNotification"]
                ),
            ]
        )

        let result = try runVerifier([fixture.path])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("notification OSC smoke trace verified"))
    }

    @Test("verifier reports missing records as contract failures")
    func verifierReportsMissingRecordsAsContractFailures() throws {
        let fixture = try makeFixture(
            named: "notification-smoke-missing-classify",
            lines: [
                try traceRecord(
                    body: "terminal.activity.observed",
                    attributes: ["agentstudio.runtime.event": "terminal.desktopNotificationRequested"]
                )
            ]
        )

        let result = try runVerifier([fixture.path])

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("missing: OSC desktop notification was classified"))
    }

    @Test("verifier accepts options before or after the trace file")
    func verifierAcceptsOptionsBeforeOrAfterTheTraceFile() throws {
        let fixture = try makeBellFixture()

        let flagBeforeTrace = try runVerifier(["--expect-bell-notified", fixture.path])
        let flagAfterTrace = try runVerifier([fixture.path, "--expect-bell-notified"])

        #expect(flagBeforeTrace.exitCode == 0)
        #expect(flagAfterTrace.exitCode == 0)
    }

    @Test("verifier reports JSONL parse errors as tooling failures")
    func verifierReportsJSONLParseErrorsAsToolingFailures() throws {
        let fixture = try makeFixture(named: "notification-smoke-bad-json", lines: ["{bad json"])

        let result = try runVerifier([fixture.path])

        #expect(result.exitCode == 2)
        #expect(result.stderr.contains("jq failed while checking"))
        #expect(!result.stderr.contains("missing:"))
    }

    @Test("verifier shows help regardless of argument order")
    func verifierShowsHelpRegardlessOfArgumentOrder() throws {
        let fixture = try makeFixture(named: "notification-smoke-help", lines: [])

        let result = try runVerifier([fixture.path, "--help"])

        #expect(result.exitCode == 2)
        #expect(result.stdout.contains("Usage:"))
        #expect(result.stderr.isEmpty)
    }

    private func makeBellFixture() throws -> URL {
        try makeFixture(
            named: "notification-smoke-bell-pass",
            lines: [
                try traceRecord(
                    body: "terminal.activity.observed",
                    attributes: ["agentstudio.runtime.event": "terminal.desktopNotificationRequested"]
                ),
                try traceRecord(
                    body: "inbox.classify",
                    attributes: [
                        "agentstudio.runtime.event": "terminal.desktopNotificationRequested",
                        "agentstudio.inbox.decision": "notify",
                    ]
                ),
                try traceRecord(
                    body: "inbox.promote",
                    attributes: [
                        "agentstudio.inbox.kind": "agentDesktopNotification",
                        "agentstudio.inbox.decision": "promote",
                    ]
                ),
                try traceRecord(
                    body: "inbox.notification.appended",
                    attributes: ["agentstudio.inbox.kind": "agentDesktopNotification"]
                ),
                try traceRecord(
                    body: "terminal.activity.observed",
                    attributes: ["agentstudio.runtime.event": "terminal.bellRang"]
                ),
                try traceRecord(
                    body: "inbox.notification.appended",
                    attributes: ["agentstudio.inbox.kind": "bellRang"]
                ),
            ]
        )
    }

    private func makeFixture(named name: String, lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(name)-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func traceRecord(body: String, attributes: [String: String]) throws -> String {
        let record: [String: Any] = [
            "body": body,
            "attributes": attributes,
        ]
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        guard let encodedRecord = String(bytes: data, encoding: .utf8) else {
            throw VerifierTestError.invalidUTF8Record
        }
        return encodedRecord
    }

    private func runVerifier(_ arguments: [String]) throws -> VerifierResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bash", "scripts/verify-notification-osc-smoke.sh"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        return VerifierResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}

private struct VerifierResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private enum VerifierTestError: Error {
    case invalidUTF8Record
}
