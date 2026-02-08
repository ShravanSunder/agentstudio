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
