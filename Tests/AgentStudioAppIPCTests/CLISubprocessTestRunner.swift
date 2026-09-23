import AgentStudioInfrastructure
import Dispatch
import Foundation
import Testing

enum CLISubprocessTestError: Error {
    case subprocessTimedOut
}

struct CLIProcessResult {
    let exitCode: Int32
    let standardOutput: Data
    let standardError: Data
}

func cliExecutableURL() throws -> URL {
    let buildDirectory = try #require(ProcessInfo.processInfo.environment["SWIFT_BUILD_DIR"])
    let testFileURL = URL(fileURLWithPath: #filePath)
    let projectRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let resolvedBuildDirectory =
        buildDirectory.hasPrefix("/")
        ? URL(fileURLWithPath: buildDirectory)
        : projectRoot.appending(path: buildDirectory)
    return resolvedBuildDirectory.appending(path: "debug/agentstudio-cli")
}

/// A hang guard, not a performance assertion.
///
/// Ten seconds was close enough to what a CLI subprocess and a real server
/// harness take under the fully parallel fast lane that it failed the run
/// rather than catching anything. No case here asserts elapsed time, so the
/// only job left is to end a process that will never exit.
private let cliSubprocessTimeout = DispatchTimeInterval.seconds(120)

/// How long a stranded child gets to honour SIGTERM before it is killed.
private let cliSubprocessTerminationGrace = DispatchTimeInterval.seconds(5)

/// Runs the built CLI off the cooperative pool and writes both streams to files.
///
/// Two hazards shape this, and both have already cost a CI run:
///
/// - Swift Testing runs each test body as a task on the cooperative executor,
///   whose width is the machine's core count, and `AgentStudioAppIPCServer`
///   answers every accepted connection from a `Task` on that same pool. Waiting
///   for the child on the test's own thread starves the server the child is
///   waiting on, so a three-core runner deadlocks the whole lane once enough
///   blocking cases run at once. The wait happens on a libdispatch thread,
///   which grows on demand, and the caller suspends instead of blocking.
/// - `command.list` returns more than a pipe buffer holds. Reading a pipe only
///   after the child exits deadlocks as soon as the child fills that buffer, so
///   both channels go to files the way the App-target runner does.
func runCLI(
    executableURL: URL,
    arguments: [String],
    environment: [String: String]
) async throws -> CLIProcessResult {
    let standardOutputURL = FileManager.default.temporaryDirectory
        .appending(path: "as-cli-out-\(UUIDv7.generate().uuidString)")
    let standardErrorURL = FileManager.default.temporaryDirectory
        .appending(path: "as-cli-err-\(UUIDv7.generate().uuidString)")
    FileManager.default.createFile(atPath: standardOutputURL.path, contents: nil)
    FileManager.default.createFile(atPath: standardErrorURL.path, contents: nil)
    defer {
        try? FileManager.default.removeItem(at: standardOutputURL)
        try? FileManager.default.removeItem(at: standardErrorURL)
    }

    let exitCode: Int32 = try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let standardOutputHandle = try FileHandle(forWritingTo: standardOutputURL)
                let standardErrorHandle = try FileHandle(forWritingTo: standardErrorURL)
                defer {
                    try? standardOutputHandle.close()
                    try? standardErrorHandle.close()
                }
                let process = Process()
                let completion = DispatchSemaphore(value: 0)
                process.executableURL = executableURL
                process.arguments = arguments
                process.environment = environment
                process.standardOutput = standardOutputHandle
                process.standardError = standardErrorHandle
                process.terminationHandler = { _ in completion.signal() }
                try process.run()
                guard completion.wait(timeout: .now() + cliSubprocessTimeout) == .success else {
                    endStrandedCLISubprocess(process, completion: completion)
                    continuation.resume(throwing: CLISubprocessTestError.subprocessTimedOut)
                    return
                }
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    return CLIProcessResult(
        exitCode: exitCode,
        standardOutput: (try? Data(contentsOf: standardOutputURL)) ?? Data(),
        standardError: (try? Data(contentsOf: standardErrorURL)) ?? Data()
    )
}

/// SIGTERM first, SIGKILL if that is ignored, and a bounded reap either way.
///
/// `waitUntilExit()` on its own is unbounded: a child that ignores termination
/// would hold this thread, and its own process, for the rest of the run. The
/// timed-out case is exactly the case that must not leak.
private func endStrandedCLISubprocess(_ process: Process, completion: DispatchSemaphore) {
    process.terminate()
    guard completion.wait(timeout: .now() + cliSubprocessTerminationGrace) != .success else { return }
    kill(process.processIdentifier, SIGKILL)
    _ = completion.wait(timeout: .now() + cliSubprocessTerminationGrace)
}
