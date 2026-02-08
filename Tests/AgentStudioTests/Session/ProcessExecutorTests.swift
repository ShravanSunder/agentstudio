import XCTest
@testable import AgentStudio

final class ProcessExecutorTests: XCTestCase {
    private var executor: DefaultProcessExecutor!

    override func setUp() {
        super.setUp()
        executor = DefaultProcessExecutor()
    }

    // MARK: - Basic Execution

    func test_execute_capturesStdout() async throws {
        // Act
        let result = try await executor.execute(
            command: "echo",
            args: ["hello"],
            cwd: nil,
            environment: nil
        )

        // Assert
        XCTAssertEqual(result.stdout, "hello")
        XCTAssertTrue(result.succeeded)
    }

    func test_execute_capturesExitCode() async throws {
        // Act
        let result = try await executor.execute(
            command: "false",
            args: [],
            cwd: nil,
            environment: nil
        )

        // Assert
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertFalse(result.succeeded)
    }

    func test_execute_respectsCwd() async throws {
        // Act
        let result = try await executor.execute(
            command: "pwd",
            args: [],
            cwd: URL(fileURLWithPath: "/tmp"),
            environment: nil
        )

        // Assert — macOS may resolve /tmp to /private/tmp
        XCTAssertTrue(
            result.stdout.contains("/tmp"),
            "Expected stdout to contain /tmp, got: \(result.stdout)"
        )
    }

    // MARK: - Environment

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
        XCTAssertTrue(
            result.stdout.contains("AGENTSTUDIO_TEST_VAR=test_value_12345"),
            "Expected env to contain custom var"
        )
    }

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

        XCTAssertNotNil(pathLine, "Expected PATH in environment output")
        if let pathLine {
            XCTAssertTrue(
                pathLine.contains("/opt/homebrew/bin") || pathLine.contains("/usr/local/bin"),
                "Expected PATH to include homebrew or local bin paths"
            )
        }
    }

    // MARK: - Timeout

    func test_execute_timeoutTerminatesHangingProcess() async throws {
        // Arrange — executor with a 2-second timeout
        let shortTimeoutExecutor = DefaultProcessExecutor(timeout: 2)

        // Act — `sleep 60` would hang for 60s, but timeout should kill it in ~2s
        do {
            _ = try await shortTimeoutExecutor.execute(
                command: "sleep",
                args: ["60"],
                cwd: nil,
                environment: nil
            )
            XCTFail("Expected ProcessError.timedOut to be thrown")
        } catch let error as ProcessError {
            // Assert
            if case .timedOut(let cmd, let seconds) = error {
                XCTAssertEqual(cmd, "sleep")
                XCTAssertEqual(seconds, 2)
            } else {
                XCTFail("Expected .timedOut, got: \(error)")
            }
        }
    }

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
        XCTAssertEqual(result.stdout, "fast")
        XCTAssertTrue(result.succeeded)
    }

    // MARK: - Regression: Fast Exit (Group 8)

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
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.succeeded)
    }
}
