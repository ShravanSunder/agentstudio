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

    // MARK: - Ghost Config Path Safety (regression: pkill -f "AgentStudio" killing tmux server)

    func test_ghostConfigPath_doesNotContainUppercaseAgentStudio() {
        // The ghost.conf path is embedded in the tmux server's command line via -f.
        // If it contains "AgentStudio" (mixed case), then `pkill -f "AgentStudio"`
        // will match the tmux server process and kill it, destroying all sessions.
        // The path must use only lowercase (e.g., ~/.agentstudio/tmux/ghost.conf).

        // Act
        let config = SessionConfiguration.detect()

        // Assert
        XCTAssertFalse(
            config.ghostConfigPath.contains("AgentStudio"),
            "ghostConfigPath must not contain 'AgentStudio' (mixed case) — "
            + "it would cause pkill -f 'AgentStudio' to kill the tmux server. "
            + "Got: \(config.ghostConfigPath)"
        )
    }

    func test_ghostConfigPath_copiedToSafeLocation() {
        // Act
        let config = SessionConfiguration.detect()

        // Assert — should be under ~/.agentstudio/tmux/
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let expectedPrefix = homeDir + "/.agentstudio/tmux/"
        XCTAssertTrue(
            config.ghostConfigPath.hasPrefix(expectedPrefix),
            "ghostConfigPath should be under ~/.agentstudio/tmux/, got: \(config.ghostConfigPath)"
        )
    }

    func test_ghostConfigPath_fileExists() {
        // Act
        let config = SessionConfiguration.detect()

        // Assert
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: config.ghostConfigPath),
            "ghost.conf should exist at resolved path: \(config.ghostConfigPath)"
        )
    }

    func test_ghostConfigPath_containsDestroyUnattachedOff() throws {
        // The ghost.conf must contain `destroy-unattached off` for tmux sessions
        // to survive when the app (and its attached clients) terminates.

        // Act
        let config = SessionConfiguration.detect()
        let contents = try String(contentsOfFile: config.ghostConfigPath, encoding: .utf8)

        // Assert
        XCTAssertTrue(
            contents.contains("destroy-unattached off"),
            "ghost.conf must contain 'destroy-unattached off' for session persistence"
        )
        XCTAssertTrue(
            contents.contains("exit-unattached off"),
            "ghost.conf must contain 'exit-unattached off' to keep server alive"
        )
    }

    func test_ghostConfigPath_disablesTmuxMouseInteraction() throws {
        // tmux must remain headless/non-interactive in Surface.
        // Scroll input should never trigger tmux copy-mode overlays.

        // Act
        let config = SessionConfiguration.detect()
        let contents = try String(contentsOfFile: config.ghostConfigPath, encoding: .utf8)

        // Assert
        XCTAssertTrue(
            contents.contains("set -g mouse off"),
            "ghost.conf must contain 'set -g mouse off' to keep tmux non-interactive"
        )
        XCTAssertTrue(
            contents.contains("unbind -a"),
            "ghost.conf must unbind tmux keys to prevent interactive tmux overlays"
        )
    }
}
