import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct AtomLibCompileFailureScriptTests {
    @Test
    func compileFailureDriverRejectsNonSendableEagerDerivedAtomRequest() async throws {
        let result = try await runAtomLibCompileFailureDriver()

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        #expect(
            result.stdout.contains(
                "[atomlib-compile-negative] PASS EagerDerivedAtom rejects a non-Sendable request"
            ))
    }

    /// The driver runs a standalone `swiftc -typecheck`, whose duration is a
    /// function of machine speed, so the test carries no clock of its own: the
    /// runner-owned hang bound is the only elapsed-time limit. The wait runs on
    /// a real thread so it cannot starve the cooperative pool.
    private func runAtomLibCompileFailureDriver() async throws -> AtomLibCompileFailureDriverOutput {
        try await withoutBlockingCooperativePool {
            let stdoutURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("agentstudio-atomlib-compile-stdout-\(UUIDv7.generate().uuidString).log")
            let stderrURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("agentstudio-atomlib-compile-stderr-\(UUIDv7.generate().uuidString).log")
            FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
            FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
            defer {
                try? FileManager.default.removeItem(at: stdoutURL)
                try? FileManager.default.removeItem(at: stderrURL)
            }
            let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
            let stderrHandle = try FileHandle(forWritingTo: stderrURL)
            defer {
                try? stdoutHandle.close()
                try? stderrHandle.close()
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["scripts/verify-atomlib-compile-failures.sh"]
            process.currentDirectoryURL = URL(
                filePath: FileManager.default.currentDirectoryPath,
                directoryHint: .isDirectory
            )
            process.standardOutput = stdoutHandle
            process.standardError = stderrHandle

            try process.run()
            process.waitUntilExit()

            return AtomLibCompileFailureDriverOutput(
                exitCode: process.terminationStatus,
                stdout: try String(contentsOf: stdoutURL, encoding: .utf8),
                stderr: try String(contentsOf: stderrURL, encoding: .utf8)
            )
        }
    }
}

private struct AtomLibCompileFailureDriverOutput: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
