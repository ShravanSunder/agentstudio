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

    func test_isOperational_requiresEnabledAndZmx() {
        // enabled + zmx → operational
        let withZmx = SessionConfiguration(
            isEnabled: true,
            zmxPath: "/usr/local/bin/zmx",
            zmxDir: "/tmp/zmx",
            healthCheckInterval: 30,
            maxCheckpointAge: 604_800
        )
        XCTAssertTrue(withZmx.isOperational)

        // enabled + no zmx → not operational
        let noZmx = SessionConfiguration(
            isEnabled: true,
            zmxPath: nil,
            zmxDir: "/tmp/zmx",
            healthCheckInterval: 30,
            maxCheckpointAge: 604_800
        )
        XCTAssertFalse(noZmx.isOperational)

        // disabled + zmx → not operational
        let disabled = SessionConfiguration(
            isEnabled: false,
            zmxPath: "/usr/local/bin/zmx",
            zmxDir: "/tmp/zmx",
            healthCheckInterval: 30,
            maxCheckpointAge: 604_800
        )
        XCTAssertFalse(disabled.isOperational)

        // disabled + no zmx → not operational
        let both = SessionConfiguration(
            isEnabled: false,
            zmxPath: nil,
            zmxDir: "/tmp/zmx",
            healthCheckInterval: 30,
            maxCheckpointAge: 604_800
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

    // MARK: - zmxDir

    func test_zmxDir_pointsToAgentStudioSubdir() {
        // Act
        let config = SessionConfiguration.detect()

        // Assert — should be under ~/.agentstudio/zmx/
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertTrue(
            config.zmxDir.hasPrefix(homeDir + "/.agentstudio/zmx"),
            "zmxDir should be under ~/.agentstudio/zmx/, got: \(config.zmxDir)"
        )
    }

    // MARK: - Terminfo Discovery (Ghostty's own terminfo, independent of zmx)

    func test_resolveTerminfoDir_findsXtermGhostty() {
        // resolveTerminfoDir() must find the terminfo directory
        // containing xterm-ghostty for Ghostty's native TERM.

        // Act
        let terminfoDir = SessionConfiguration.resolveTerminfoDir()

        // Assert
        XCTAssertNotNil(terminfoDir, "resolveTerminfoDir() must find the terminfo directory")
        if let dir = terminfoDir {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: dir + "/78/xterm-ghostty"),
                "terminfoDir must contain 78/xterm-ghostty: \(dir)"
            )
        }
    }

    func test_customTerminfo_xterm256color_existsInBundle() {
        // Our custom xterm-256color terminfo must be bundled alongside
        // xterm-ghostty for terminal capability resolution.

        // Act — find the terminfo directory in the SPM resource bundle
        guard let bundleURL = Bundle.module.url(forResource: "terminfo", withExtension: nil),
            let contents = try? FileManager.default.contentsOfDirectory(
                at: bundleURL.appendingPathComponent("78"),
                includingPropertiesForKeys: nil
            )
        else {
            XCTFail("terminfo/78/ directory not found in bundle")
            return
        }

        // Assert — both xterm-ghostty and xterm-256color must be present
        let filenames = contents.map { $0.lastPathComponent }
        XCTAssertTrue(
            filenames.contains("xterm-ghostty"),
            "terminfo/78/ must contain xterm-ghostty (from Ghostty build)"
        )
        XCTAssertTrue(
            filenames.contains("xterm-256color"),
            "terminfo/78/ must contain custom xterm-256color"
        )
    }
}
