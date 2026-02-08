import XCTest
@testable import AgentStudio

final class SessionConfigurationTests: XCTestCase {

    // MARK: - isEnabled Parsing

    func test_isEnabled_defaultsToTrue() {
        // Arrange — no AGENTSTUDIO_SESSION_RESTORE in env
        let env: [String: String] = [:]

        // Act
        let config = SessionConfiguration.detect(environment: env)

        // Assert
        XCTAssertTrue(config.isEnabled)
    }

    func test_isEnabled_parsesTrue() {
        // Arrange
        let env = ["AGENTSTUDIO_SESSION_RESTORE": "true"]

        // Act
        let config = SessionConfiguration.detect(environment: env)

        // Assert
        XCTAssertTrue(config.isEnabled)
    }

    func test_isEnabled_parses1() {
        // Arrange
        let env = ["AGENTSTUDIO_SESSION_RESTORE": "1"]

        // Act
        let config = SessionConfiguration.detect(environment: env)

        // Assert
        XCTAssertTrue(config.isEnabled)
    }

    func test_isEnabled_parsesFalse() {
        // Arrange
        let env = ["AGENTSTUDIO_SESSION_RESTORE": "false"]

        // Act
        let config = SessionConfiguration.detect(environment: env)

        // Assert
        XCTAssertFalse(config.isEnabled)
    }

    // MARK: - isOperational

    func test_isOperational_requiresEnabledAndTmux() {
        // Arrange & Act & Assert

        // enabled + tmux → operational
        let withTmux = SessionConfiguration(
            isEnabled: true,
            tmuxPath: "/usr/bin/tmux",
            ghostConfigPath: "/tmp/ghost.conf",
            healthCheckInterval: 30,
            socketDirectory: "/tmp",
            socketName: "agentstudio",
            maxCheckpointAge: 604800
        )
        XCTAssertTrue(withTmux.isOperational)

        // enabled + no tmux → not operational
        let noTmux = SessionConfiguration(
            isEnabled: true,
            tmuxPath: nil,
            ghostConfigPath: "/tmp/ghost.conf",
            healthCheckInterval: 30,
            socketDirectory: "/tmp",
            socketName: "agentstudio",
            maxCheckpointAge: 604800
        )
        XCTAssertFalse(noTmux.isOperational)

        // disabled + tmux → not operational
        let disabled = SessionConfiguration(
            isEnabled: false,
            tmuxPath: "/usr/bin/tmux",
            ghostConfigPath: "/tmp/ghost.conf",
            healthCheckInterval: 30,
            socketDirectory: "/tmp",
            socketName: "agentstudio",
            maxCheckpointAge: 604800
        )
        XCTAssertFalse(disabled.isOperational)

        // disabled + no tmux → not operational
        let both = SessionConfiguration(
            isEnabled: false,
            tmuxPath: nil,
            ghostConfigPath: "/tmp/ghost.conf",
            healthCheckInterval: 30,
            socketDirectory: "/tmp",
            socketName: "agentstudio",
            maxCheckpointAge: 604800
        )
        XCTAssertFalse(both.isOperational)
    }

    // MARK: - Health Check Interval

    func test_healthCheckInterval_parsesFromEnv() {
        // Arrange
        let env = ["AGENTSTUDIO_HEALTH_INTERVAL": "60"]

        // Act
        let config = SessionConfiguration.detect(environment: env)

        // Assert
        XCTAssertEqual(config.healthCheckInterval, 60.0)
    }

    func test_healthCheckInterval_defaultsTo30() {
        // Arrange — no AGENTSTUDIO_HEALTH_INTERVAL in env
        let env: [String: String] = [:]

        // Act
        let config = SessionConfiguration.detect(environment: env)

        // Assert
        XCTAssertEqual(config.healthCheckInterval, 30.0)
    }
}
