import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation

/// A `ProcessExecutor` that runs every command to exit, with no timeout.
///
/// Tests use it wherever they would have constructed `DefaultProcessExecutor`,
/// whose per-call timeout decides a test by machine speed: directly for script
/// runs, or injected into a product owner such as a git status provider.
/// `runCommandToExit` in `AgentStudioTestSupport` owns the command contract and
/// the wait; this type only adapts it to the product protocol, which that target
/// cannot import.
struct RunToExitProcessExecutor: ProcessExecutor {
    func execute(
        command: String,
        args: [String],
        cwd: URL?,
        environment: [String: String]?
    ) async throws -> ProcessResult {
        let result = try await runCommandToExit(
            command: command,
            arguments: args,
            currentDirectoryURL: cwd,
            environment: environment
        )
        return ProcessResult(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr)
    }
}
