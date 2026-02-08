import Foundation
import XCTest
@testable import AgentStudio

enum MockExecutorError: Error {
    case noResponseQueued
}

/// Mock executor that records calls and returns canned responses.
final class MockProcessExecutor: ProcessExecutor, @unchecked Sendable {
    struct Call: Equatable {
        let command: String
        let args: [String]
    }

    var calls: [Call] = []
    var responses: [ProcessResult] = []
    private var responseIndex = 0

    /// Queue a response for the next `execute` call.
    func enqueue(_ result: ProcessResult) {
        responses.append(result)
    }

    /// Queue a successful response with given stdout.
    func enqueueSuccess(_ stdout: String = "") {
        enqueue(ProcessResult(exitCode: 0, stdout: stdout, stderr: ""))
    }

    /// Queue a failure response.
    func enqueueFailure(_ stderr: String = "error") {
        enqueue(ProcessResult(exitCode: 1, stdout: "", stderr: stderr))
    }

    func execute(
        command: String,
        args: [String],
        cwd: URL?,
        environment: [String: String]?
    ) async throws -> ProcessResult {
        calls.append(Call(command: command, args: args))

        guard responseIndex < responses.count else {
            XCTFail("MockProcessExecutor: no response queued for call #\(responseIndex + 1): \(command) \(args)")
            throw MockExecutorError.noResponseQueued
        }

        let result = responses[responseIndex]
        responseIndex += 1
        return result
    }
}
