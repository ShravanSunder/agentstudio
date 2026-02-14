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
        // ghost.conf must NOT use `unbind -a` — it destroys key tables, causing
        // "table doesn't exist" errors when buildAttachCommand's inline hardening
        // runs `unbind-key -a -T <table>`. Individual unbinds are used instead.
        // The inline hardening in buildAttachCommand handles broad table clearing.
        XCTAssertTrue(
            contents.contains("unbind -T root WheelUpPane"),
            "ghost.conf must individually unbind WheelUpPane from root table"
        )
        XCTAssertTrue(
            contents.contains("unbind -T root MouseDown1Pane"),
            "ghost.conf must individually unbind MouseDown1Pane from root table"
        )
    }

    func test_ghostConfigPath_explicitlyUnbindsMouseWheelEvents() throws {
        // Belt-and-suspenders: WheelUpPane/WheelDownPane must be explicitly
        // unbound in root and copy-mode tables. Some tmux versions re-create
        // default bindings after `unbind -a`.

        // Act
        let config = SessionConfiguration.detect()
        let contents = try String(contentsOfFile: config.ghostConfigPath, encoding: .utf8)

        // Assert
        XCTAssertTrue(
            contents.contains("unbind -T root WheelUpPane"),
            "ghost.conf must explicitly unbind WheelUpPane from root table"
        )
        XCTAssertTrue(
            contents.contains("unbind -T root WheelDownPane"),
            "ghost.conf must explicitly unbind WheelDownPane from root table"
        )
        XCTAssertTrue(
            contents.contains("unbind -T copy-mode WheelUpPane"),
            "ghost.conf must explicitly unbind WheelUpPane from copy-mode table"
        )
        XCTAssertTrue(
            contents.contains("unbind -T copy-mode-vi WheelUpPane"),
            "ghost.conf must explicitly unbind WheelUpPane from copy-mode-vi table"
        )
    }

    func test_ghostConfigPath_disablesAlternateScreen() throws {
        // tmux must NOT enter alternate screen mode on the outer terminal.
        // Without alternate screen, Ghostty's mouse_alternate_scroll (DEC 1007,
        // default ON) won't trigger — Ghostty handles scroll as internal viewport
        // scrollback instead of converting scroll to cursor keys sent to tmux.

        // Act
        let config = SessionConfiguration.detect()
        let contents = try String(contentsOfFile: config.ghostConfigPath, encoding: .utf8)

        // Assert — smcup@:rmcup@ must be present for xterm-ghostty (primary outer TERM)
        XCTAssertTrue(
            contents.contains("smcup@:rmcup@"),
            "ghost.conf must disable alternate screen via smcup@:rmcup@ terminal-overrides"
        )
    }

    // MARK: - Custom xterm-256color Terminfo

    func test_customTerminfo_xterm256color_existsInBundle() {
        // Our custom xterm-256color terminfo must be bundled alongside
        // xterm-ghostty. It provides full Ghostty visual capabilities
        // (RGB, underlines, sync) for programs inside tmux without
        // the Kitty keyboard protocol conflict.

        // Act — find the terminfo directory in the SPM resource bundle
        guard let bundleURL = Bundle.module.url(forResource: "terminfo", withExtension: nil),
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: bundleURL.appendingPathComponent("78"),
                  includingPropertiesForKeys: nil
              ) else {
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
            "terminfo/78/ must contain custom xterm-256color (git-tracked, not from build)"
        )
    }

    func test_ghostConfigPath_injectsTerminfoPath() throws {
        // The ghost.conf copied to ~/.agentstudio/tmux/ must contain a
        // set-environment -g TERMINFO directive pointing to our custom terminfo.
        // This ensures programs inside tmux find our xterm-256color (SGR mouse)
        // instead of the system one, even when the tmux server persists across
        // app restarts with a stale initial environment.

        // Act
        let config = SessionConfiguration.detect()
        let contents = try String(contentsOfFile: config.ghostConfigPath, encoding: .utf8)

        // Assert — must contain TERMINFO injection
        XCTAssertTrue(
            contents.contains("set-environment -g TERMINFO"),
            "ghost.conf must inject TERMINFO via set-environment for custom xterm-256color"
        )
    }

    func test_resolveTerminfoDir_findsCustomXterm256color() {
        // resolveTerminfoDir() must find our custom terminfo directory
        // containing xterm-256color with SGR mouse capabilities.

        // Act
        let terminfoDir = SessionConfiguration.resolveTerminfoDir()

        // Assert
        XCTAssertNotNil(terminfoDir, "resolveTerminfoDir() must find the terminfo directory")
        if let dir = terminfoDir {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: dir + "/78/xterm-256color"),
                "terminfoDir must contain 78/xterm-256color: \(dir)"
            )
        }
    }

    func test_customTerminfo_xterm256color_hasSGRMouse() throws {
        // The custom xterm-256color must use SGR mouse format (kmous=\E[<)
        // matching Ghostty's native format. The system xterm-256color uses
        // X10 format (kmous=\E[M) which causes protocol mismatches when
        // tmux translates between inner and outer terminal mouse formats.

        // Act — verify via infocmp that the bundled terminfo has SGR mouse
        guard let bundleURL = Bundle.module.url(forResource: "terminfo", withExtension: nil) else {
            XCTFail("terminfo directory not found in bundle")
            return
        }
        let terminfoDir = bundleURL.path

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/infocmp")
        process.arguments = ["-x", "-A", terminfoDir, "xterm-256color"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        // Assert — must contain SGR mouse, RGB, styled underlines, sync
        XCTAssertTrue(output.contains("kmous=\\E[<"), "Custom xterm-256color must use SGR mouse (kmous=\\E[<)")
        XCTAssertTrue(output.contains("Tc"), "Custom xterm-256color must have Tc (true color)")
        XCTAssertTrue(output.contains("Smulx"), "Custom xterm-256color must have Smulx (styled underlines)")
        XCTAssertTrue(output.contains("Setulc"), "Custom xterm-256color must have Setulc (underline colors)")
        XCTAssertTrue(output.contains("Sync"), "Custom xterm-256color must have Sync (synchronized output)")
    }
}
