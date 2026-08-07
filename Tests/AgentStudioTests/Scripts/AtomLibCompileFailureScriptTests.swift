import Foundation
import Testing

@testable import AgentStudioInfrastructure

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

    private func runAtomLibCompileFailureDriver() async throws -> ProcessResult {
        try await DefaultProcessExecutor(timeout: 30).execute(
            command: "/bin/bash",
            args: ["scripts/verify-atomlib-compile-failures.sh"],
            cwd: URL(
                filePath: FileManager.default.currentDirectoryPath,
                directoryHint: .isDirectory
            ),
            environment: nil
        )
    }
}
