import Foundation
import Testing

@testable import AgentStudio

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

    // MARK: - Timeout

    @Test
    func test_execute_timeoutTerminatesHangingProcess() async throws {
        // Arrange — executor with a 2-second timeout
        let shortTimeoutExecutor = DefaultProcessExecutor(timeout: 2)

        // Act — `sleep 20` would hang for 20s, but timeout should kill it in ~2s.
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
                #expect(seconds == 2)
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
}
