import Darwin
import Foundation
import Testing

@testable import AgentStudioInfrastructure

@Suite(.serialized)
final class ProcessExecutorTests {
    private var executor: DefaultProcessExecutor!

    init() {
        executor = DefaultProcessExecutor()
    }

    // MARK: - Basic Execution

    @Test
    func test_execute_capturesStdout() async throws {
        // Act
        let result = try await executor.execute(
            command: "echo",
            args: ["hello"],
            cwd: nil,
            environment: nil
        )

        // Assert
        #expect(result.stdout == "hello")
        #expect(result.succeeded)
    }

    @Test
    func test_execute_capturesExitCode() async throws {
        // Act
        let result = try await executor.execute(
            command: "false",
            args: [],
            cwd: nil,
            environment: nil
        )

        // Assert
        #expect(result.exitCode == 1)
        #expect(!result.succeeded)
    }

    @Test
    func test_execute_respectsCwd() async throws {
        // Act
        let result = try await executor.execute(
            command: "pwd",
            args: [],
            cwd: URL(fileURLWithPath: "/tmp"),
            environment: nil
        )

        // Assert — macOS may resolve /tmp to /private/tmp
        #expect(
            result.stdout.contains("/tmp"),
            "Expected stdout to contain /tmp, got: \(result.stdout)"
        )
    }

    // MARK: - Environment

    @Test
    func test_execute_mergesEnvironmentOverrides() async throws {
        // Arrange
        let customEnv = ["AGENTSTUDIO_TEST_VAR": "test_value_12345"]

        // Act
        let result = try await executor.execute(
            command: "env",
            args: [],
            cwd: nil,
            environment: customEnv
        )

        // Assert
        #expect(
            result.stdout.contains("AGENTSTUDIO_TEST_VAR=test_value_12345"),
            "Expected env to contain custom var"
        )
    }

    @Test
    func test_execute_preservesPathPrefix() async throws {
        // Act
        let result = try await executor.execute(
            command: "env",
            args: [],
            cwd: nil,
            environment: nil
        )

        // Assert — verify homebrew/local paths are prepended
        let pathLine = result.stdout
            .components(separatedBy: "\n")
            .first { $0.hasPrefix("PATH=") }

        #expect(pathLine != nil, "Expected PATH in environment output")
        if let pathLine {
            #expect(
                pathLine.contains("/opt/homebrew/bin") || pathLine.contains("/usr/local/bin"),
                "Expected PATH to include homebrew or local bin paths"
            )
        }
    }

    @Test
    func test_execute_rebuildsPathWhenOverrideIsEmpty() async throws {
        // Act
        let result = try await executor.execute(
            command: "env",
            args: [],
            cwd: nil,
            environment: ["PATH": ""]
        )

        // Assert
        let pathLine = result.stdout
            .components(separatedBy: "\n")
            .first { $0.hasPrefix("PATH=") }

        #expect(pathLine != nil, "Expected PATH in environment output")
        if let pathLine {
            #expect(pathLine.contains("/opt/homebrew/bin"))
            #expect(pathLine.contains("/usr/local/bin"))
            #expect(pathLine.contains("/usr/bin"))
        }
    }

    @Test
    func test_execute_rebuildsHomeWhenOverrideIsEmpty() async throws {
        // Act
        let result = try await executor.execute(
            command: "env",
            args: [],
            cwd: nil,
            environment: ["HOME": ""]
        )

        // Assert
        let homeLine = result.stdout
            .components(separatedBy: "\n")
            .first { $0.hasPrefix("HOME=") }

        #expect(homeLine != nil, "Expected HOME in environment output")
        if let homeLine {
            #expect(homeLine.count > "HOME=".count)
            #expect(homeLine != "HOME=")
        }
    }

    // MARK: - Timeout

    @Test
    func test_execute_timeoutTerminatesHangingProcess() async throws {
        // Arrange — keep timeout short to validate behavior without a multi-second wall-clock hit.
        let timeoutSeconds: TimeInterval = 0.35
        let shortTimeoutExecutor = DefaultProcessExecutor(timeout: timeoutSeconds)

        // Act — `sleep 20` would hang for 20s, but timeout should kill it quickly.
        // Keep the fallback sleep bounded so failure modes do not burn a full minute.
        do {
            _ = try await shortTimeoutExecutor.execute(
                command: "sleep",
                args: ["20"],
                cwd: nil,
                environment: nil
            )
            Issue.record("Expected ProcessError.timedOut to be thrown")
        } catch let error as ProcessError {
            // Assert
            if case .timedOut(let cmd, let seconds) = error {
                #expect(cmd == "sleep")
                #expect(seconds == timeoutSeconds)
            } else {
                Issue.record("Expected .timedOut, got: \(error)")
            }
        } catch {
            Issue.record("Expected .timedOut, got: \(error)")
        }
    }

    @Test
    func test_execute_normalCommandDoesNotTimeout() async throws {
        // Arrange — short timeout but the command finishes quickly
        let shortTimeoutExecutor = DefaultProcessExecutor(timeout: 5)

        // Act
        let result = try await shortTimeoutExecutor.execute(
            command: "echo",
            args: ["fast"],
            cwd: nil,
            environment: nil
        )

        // Assert — should succeed normally, no timeout
        #expect(result.stdout == "fast")
        #expect(result.succeeded)
    }

    @Test
    func test_execute_concurrentTimeoutsDoNotStarve() async throws {
        let timeoutSeconds: TimeInterval = 0.35
        let concurrentExecutor = DefaultProcessExecutor(timeout: timeoutSeconds)
        let clock = ContinuousClock()
        let start = clock.now

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    do {
                        _ = try await concurrentExecutor.execute(
                            command: "sleep",
                            args: ["20"],
                            cwd: nil,
                            environment: nil
                        )
                        Issue.record("Expected concurrent sleep command to time out")
                    } catch let error as ProcessError {
                        guard case .timedOut(let command, let seconds) = error else {
                            Issue.record("Expected .timedOut, got: \(error)")
                            return
                        }
                        #expect(command == "sleep")
                        #expect(seconds == timeoutSeconds)
                    } catch {
                        Issue.record("Expected .timedOut, got: \(error)")
                    }
                }
            }

            await group.waitForAll()
        }

        let elapsed = start.duration(to: clock.now)
        #expect(elapsed < .seconds(5))
    }

    @Test
    func test_execute_cancellationWinsOverProcessTimeout() async throws {
        // Arrange — cancellation should tear down the child process promptly instead of
        // waiting for the executor's subprocess timeout path to fire.
        let cancellationExecutor = DefaultProcessExecutor(timeout: 0.35)

        // Act
        let task = Task {
            try await cancellationExecutor.execute(
                command: "sleep",
                args: ["20"],
                cwd: nil,
                environment: nil
            )
        }
        task.cancel()

        // Assert
        do {
            _ = try await task.value
            Issue.record("Expected CancellationError to be thrown")
        } catch is CancellationError {
            // expected
        } catch {
            Issue.record("Expected CancellationError, got: \(error)")
        }
    }

    @Test
    func test_execute_cancellationReturnsOnlyAfterChildExit() async throws {
        // Arrange
        let processIdentifierURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-process-\(UUIDv7.generate().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: processIdentifierURL) }
        let cancellationExecutor = DefaultProcessExecutor(timeout: 20)
        let task = Task {
            try await cancellationExecutor.execute(
                command: "sh",
                args: [
                    "-c",
                    "printf '%s' \"$$\" > \"$1\"; trap '' TERM; while :; do :; done",
                    "agentstudio-process-executor-test",
                    processIdentifierURL.path,
                ],
                cwd: nil,
                environment: nil
            )
        }
        let childProcessIdentifier = try await waitForProcessIdentifier(at: processIdentifierURL)

        // Act
        task.cancel()

        // Assert
        do {
            _ = try await task.value
            Issue.record("Expected CancellationError to be thrown")
        } catch is CancellationError {
            // expected
        } catch {
            Issue.record("Expected CancellationError, got: \(error)")
        }
        errno = 0
        #expect(kill(childProcessIdentifier, 0) == -1)
        #expect(errno == ESRCH)
    }

    // MARK: - Regression: Fast Exit (Group 8)

    @Test
    func test_execute_fastExitDoesNotHang() async throws {
        // Regression test for the Group 8 fix: fast-exiting processes like
        // `true` (~0ms) must complete without hanging. The old code set
        // terminationHandler after pipe reads, missing already-exited processes.

        // Act — `true` exits immediately with code 0
        let result = try await executor.execute(
            command: "true",
            args: [],
            cwd: nil,
            environment: nil
        )

        // Assert
        #expect(result.exitCode == 0)
        #expect(result.succeeded)
    }

    private func waitForProcessIdentifier(at url: URL) async throws -> pid_t {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while clock.now < deadline {
            if let contents = try? String(contentsOf: url, encoding: .utf8),
                let processIdentifier = pid_t(contents),
                processIdentifier > 0
            {
                return processIdentifier
            }
            await Task.yield()
        }
        throw ProcessExecutorTestError.processIdentifierNotPublished
    }
}

private enum ProcessExecutorTestError: Error {
    case processIdentifierNotPublished
}
