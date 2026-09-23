import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct NotificationOSCSmokeVerifierTests {
    @Test("verifier accepts a complete notification smoke fixture")
    func verifierAcceptsCompleteNotificationSmokeFixture() async throws {
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

        let result = try await runVerifier([fixture.path])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("notification OSC smoke trace verified"))
    }

    @Test("verifier reports missing records as contract failures")
    func verifierReportsMissingRecordsAsContractFailures() async throws {
        let fixture = try makeFixture(
            named: "notification-smoke-missing-classify",
            lines: [
                try traceRecord(
                    body: "terminal.activity.observed",
                    attributes: ["agentstudio.runtime.event": "terminal.desktopNotificationRequested"]
                )
            ]
        )

        let result = try await runVerifier([fixture.path])

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("missing: OSC desktop notification was classified"))
    }

    @Test("verifier accepts options before or after the trace file")
    func verifierAcceptsOptionsBeforeOrAfterTheTraceFile() async throws {
        let fixture = try makeBellFixture()

        let flagBeforeTrace = try await runVerifier(["--expect-bell-notified", fixture.path])
        let flagAfterTrace = try await runVerifier([fixture.path, "--expect-bell-notified"])

        #expect(flagBeforeTrace.exitCode == 0)
        #expect(flagAfterTrace.exitCode == 0)
    }

    @Test("verifier reports JSONL parse errors as tooling failures")
    func verifierReportsJSONLParseErrorsAsToolingFailures() async throws {
        let fixture = try makeFixture(named: "notification-smoke-bad-json", lines: ["{bad json"])

        let result = try await runVerifier([fixture.path])

        #expect(result.exitCode == 2)
        #expect(result.stderr.contains("jq failed while checking"))
        #expect(!result.stderr.contains("missing:"))
    }

    @Test("verifier shows help regardless of argument order")
    func verifierShowsHelpRegardlessOfArgumentOrder() async throws {
        let fixture = try makeFixture(named: "notification-smoke-help", lines: [])

        let result = try await runVerifier([fixture.path, "--help"])

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

    private func runVerifier(_ arguments: [String]) async throws -> VerifierResult {
        try await withoutBlockingCooperativePool {
            let stdoutURL = FileManager.default.temporaryDirectory
                .appending(path: "notification-osc-stdout-\(UUIDv7.generate().uuidString).log")
            let stderrURL = FileManager.default.temporaryDirectory
                .appending(path: "notification-osc-stderr-\(UUIDv7.generate().uuidString).log")
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
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["bash", "scripts/verify-notification-osc-smoke.sh"] + arguments
            process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            process.standardOutput = stdoutHandle
            process.standardError = stderrHandle
            try process.run()
            process.waitUntilExit()
            try stdoutHandle.close()
            try stderrHandle.close()
            return VerifierResult(
                exitCode: process.terminationStatus,
                stdout: try String(contentsOf: stdoutURL, encoding: .utf8),
                stderr: try String(contentsOf: stderrURL, encoding: .utf8)
            )
        }
    }
}

private struct VerifierResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private enum VerifierTestError: Error {
    case invalidUTF8Record
}
