import Foundation
@testable import AgentStudio

/// Mock process executor for testing ZellijService
final class MockProcessExecutor: ProcessExecutor, @unchecked Sendable {
    /// Responses keyed by command pattern
    private var responses: [String: ProcessResult] = [:]

    /// Record of all executed commands
    private(set) var executedCommands: [[String]] = []

    func execute(_ path: String, arguments: [String]) async -> ProcessResult {
        executedCommands.append([path] + arguments)

        // Build key from command name + arguments
        let cmdName = URL(fileURLWithPath: path).lastPathComponent
        let fullCommand = ([cmdName] + arguments).joined(separator: " ")

        // Try exact match first
        if let response = responses[fullCommand] {
            return response
        }

        // Try partial matches
        for (pattern, response) in responses {
            if fullCommand.contains(pattern) {
                return response
            }
        }

        // Default: command not mocked
        return ProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "Command not mocked: \(fullCommand)"
        )
    }

    /// Set up a successful response for a command pattern
    func mockSuccess(_ pattern: String, stdout: String = "") {
        responses[pattern] = ProcessResult(exitCode: 0, stdout: stdout, stderr: "")
    }

    /// Set up a failure response for a command pattern
    func mockFailure(_ pattern: String, stderr: String) {
        responses[pattern] = ProcessResult(exitCode: 1, stdout: "", stderr: stderr)
    }

    /// Reset state between tests
    func reset() {
        responses.removeAll()
        executedCommands.removeAll()
    }

    /// Check if a command matching the pattern was executed
    func wasExecuted(_ pattern: String) -> Bool {
        executedCommands.contains { cmd in
            cmd.joined(separator: " ").contains(pattern)
        }
    }
}
