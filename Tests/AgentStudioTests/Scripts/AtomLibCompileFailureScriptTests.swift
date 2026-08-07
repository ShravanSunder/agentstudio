import Foundation
import Testing

@testable import AgentStudioInfrastructure

@Suite(.serialized)
struct AtomLibCompileFailureScriptTests {
    @Test
    func compileFailureDriverRejectsNonSendableEagerDerivedAtomRequest() throws {
        let result = try runAtomLibCompileFailureDriver()

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        #expect(
            result.stdout.contains(
                "[atomlib-compile-negative] PASS EagerDerivedAtom rejects a non-Sendable request"
            ))
    }

    private func runAtomLibCompileFailureDriver() throws -> AtomLibCompileFailureScriptResult {
        let outputIdentifier = UUIDv7.generate().uuidString
        let stdoutURL = FileManager.default.temporaryDirectory
            .appending(path: "atomlib-compile-failure-stdout-\(outputIdentifier).log")
        let stderrURL = FileManager.default.temporaryDirectory
            .appending(path: "atomlib-compile-failure-stderr-\(outputIdentifier).log")
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
        process.executableURL = URL(filePath: "/bin/bash")
        process.arguments = ["scripts/verify-atomlib-compile-failures.sh"]
        process.currentDirectoryURL = URL(
            filePath: FileManager.default.currentDirectoryPath,
            directoryHint: .isDirectory
        )
        process.environment = ProcessInfo.processInfo.environment
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        try process.run()
        process.waitUntilExit()

        return AtomLibCompileFailureScriptResult(
            exitCode: process.terminationStatus,
            stdout: try String(contentsOf: stdoutURL, encoding: .utf8),
            stderr: try String(contentsOf: stderrURL, encoding: .utf8)
        )
    }
}

private struct AtomLibCompileFailureScriptResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
