import Darwin
import Foundation
import Testing

@Suite("Observability debug launch scripts")
struct ObservabilityDebugLaunchScriptsTests {
    @Test("debug launcher uses four-character worktree code for socket path headroom")
    func debugLauncherUsesFourCharacterWorktreeCodeForSocketPathHeadroom() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }

        let result = try fixture.runScript(
            "scripts/run-debug-observability.sh",
            arguments: ["--print-identity"],
            environment: [:]
        )

        #expect(result.exitCode == 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        let codeMatch = result.stdout.firstMatch(of: /AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=([0-9a-z]+)/)
        let code = String(codeMatch?.1 ?? "")
        #expect(code.count == 4)
        #expect(code.wholeMatch(of: /[0-9a-z]{4}/) != nil)
        #expect(result.stdout.contains("Agent\\ Studio\\ Debug\\ \(code)"))
        #expect(result.stdout.contains("/.agentstudio-db/\(code)"))
    }

    @Test("debug launcher allocates a shared swift build slot by default")
    func debugLauncherAllocatesSharedSwiftBuildSlotByDefault() throws {
        let script = try String(contentsOfFile: "scripts/run-debug-observability.sh", encoding: .utf8)

        #expect(script.contains("source \"$PROJECT_ROOT/scripts/swift-build-slot.sh\" debug"))
        #expect(script.contains("swift build --build-path \"$build_path\""))
    }

    @Test("debug launcher refuses same worktree debug app outside default artifact root")
    func debugLauncherRefusesSameWorktreeDebugRuntimeByBundleIdentifier() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let debugCode = try fixture.worktreeDebugCode()
        let runningApp = try fixture.makeAppBundle(
            name: "External AgentStudio Debug \(debugCode).app",
            releaseChannel: "stable",
            bundleIdentifier: "com.agentstudio.app.debug.d\(debugCode)"
        )
        let openMarker = fixture.url("open-called")
        let stateFile = fixture.url("latest.env")

        let result = try fixture.runScript(
            "scripts/run-debug-observability.sh",
            arguments: ["--skip-build", "--detach"],
            environment: [
                "AGENTSTUDIO_OPEN_BIN": try fixture.executable(
                    "open",
                    """
                    #!/bin/bash
                    echo called > "\(openMarker.path)"
                    exit 0
                    """
                ).path,
                "AGENTSTUDIO_PGREP_BIN": try fixture.executable(
                    "pgrep",
                    """
                    #!/bin/bash
                    echo 5252
                    """
                ).path,
                "AGENTSTUDIO_LSOF_BIN": try fixture.executable(
                    "lsof",
                    """
                    #!/bin/bash
                    echo "n\(runningApp.path)/Contents/MacOS/AgentStudio"
                    """
                ).path,
                "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path,
            ]
        )

        #expect(result.exitCode == 1, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        #expect(!FileManager.default.fileExists(atPath: openMarker.path))
        let state = try String(contentsOf: stateFile, encoding: .utf8)
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_STATUS=already_running"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=\(debugCode)"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_PID=5252"))
    }

    @Test("debug launcher fails closed when running process attribution is unavailable")
    func debugLauncherFailsClosedWhenRunningProcessAttributionIsUnavailable() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")

        let result = try fixture.runScript(
            "scripts/run-debug-observability.sh",
            arguments: ["--skip-build", "--detach"],
            environment: [
                "AGENTSTUDIO_PGREP_BIN": try fixture.executable(
                    "pgrep",
                    """
                    #!/bin/bash
                    echo 5353
                    """
                ).path,
                "AGENTSTUDIO_LSOF_BIN": try fixture.executable(
                    "lsof",
                    """
                    #!/bin/bash
                    exit 1
                    """
                ).path,
                "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path,
            ]
        )

        #expect(result.exitCode == 1)
        let state = try String(contentsOf: stateFile, encoding: .utf8)
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_STATUS=launch_failed"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_REASON=duplicate_attribution_failed"))
    }

    @Test("debug launcher overwrites stale running state when collector health fails")
    func debugLauncherOverwritesStaleRunningStateWhenCollectorHealthFails() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=stale-marker
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=stale
        AGENTSTUDIO_OBSERVABILITY_PID=\(getpid())
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)

        let result = try fixture.runScript(
            "scripts/run-debug-observability.sh",
            arguments: ["--skip-build", "--detach"],
            environment: [
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "curl-fail-health",
                    """
                    #!/bin/bash
                    exit 7
                    """
                ).path,
                "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path,
            ]
        )

        #expect(result.exitCode == 1)
        let state = try String(contentsOf: stateFile, encoding: .utf8)
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_STATUS=launch_failed"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_REASON=otlp_collector_unhealthy"))
        #expect(!state.contains("stale-marker"))
    }

    @Test("debug launcher ignores stale state PID when bundle identity does not match")
    func debugLauncherIgnoresStaleStatePIDWhenBundleIdentityDoesNotMatch() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let debugCode = try fixture.worktreeDebugCode()
        let unrelatedApp = try fixture.makeAppBundle(
            name: "Unrelated AgentStudio.app",
            releaseChannel: "stable",
            bundleIdentifier: "com.agentstudio.app"
        )
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=\(debugCode)
        AGENTSTUDIO_OBSERVABILITY_PID=5454
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)
        let buildPath = try fixture.makeDebugBuildExecutable(
            """
            #!/bin/bash
            sleep 30
            """
        )

        let result = try fixture.runScript(
            "scripts/run-debug-observability.sh",
            arguments: ["--build-path", buildPath.path, "--skip-build", "--detach"],
            environment: [
                "AGENTSTUDIO_OPEN_BIN": try fixture.executable(
                    "open",
                    """
                    #!/bin/bash
                    exit 1
                    """
                ).path,
                "AGENTSTUDIO_PGREP_BIN": try fixture.executable(
                    "pgrep",
                    """
                    #!/bin/bash
                    echo 5454
                    """
                ).path,
                "AGENTSTUDIO_LSOF_BIN": try fixture.executable(
                    "lsof",
                    """
                    #!/bin/bash
                    echo "n\(unrelatedApp.path)/Contents/MacOS/AgentStudio"
                    """
                ).path,
                "AGENTSTUDIO_DITTO_BIN": try fixture.executable(
                    "ditto",
                    """
                    #!/bin/bash
                    cp -R "$1" "$2"
                    """
                ).path,
                "AGENTSTUDIO_CODESIGN_BIN": try fixture.executable(
                    "codesign",
                    """
                    #!/bin/bash
                    exit 0
                    """
                ).path,
                "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path,
            ]
        )

        #expect(result.exitCode == 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        let state = try String(contentsOf: stateFile, encoding: .utf8)
        defer {
            if let pid = state.firstMatch(of: /AGENTSTUDIO_OBSERVABILITY_PID=([0-9]+)/)?.1 {
                kill(pid_t(pid) ?? -1, SIGTERM)
            }
        }
        #expect(!state.contains("AGENTSTUDIO_OBSERVABILITY_STATUS=already_running"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_STATUS=running"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_LAUNCH_METHOD=direct_executable"))
    }

    @Test("debug launcher refuses running direct executable from state file")
    func debugLauncherRefusesRunningDirectExecutableFromStateFile() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let debugCode = try fixture.worktreeDebugCode()
        let stateFile = fixture.url("latest.env")
        let openMarker = fixture.url("open-called")
        let buildPath = fixture.url("debug-build")
        let debugPath = buildPath.appending(path: "debug")
        try FileManager.default.createDirectory(at: debugPath, withIntermediateDirectories: true)
        let executableURL = debugPath.appending(path: "AgentStudio")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: executableURL)
        chmod(executableURL.path, 0o755)
        let executablePath = buildPath.appending(path: "debug/AgentStudio").path
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=\(debugCode)
        AGENTSTUDIO_OBSERVABILITY_LAUNCH_METHOD=direct_executable
        AGENTSTUDIO_OBSERVABILITY_PID=\(getpid())
        AGENTSTUDIO_OBSERVABILITY_EXECUTABLE=\(executablePath)
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)

        let result = try fixture.runScript(
            "scripts/run-debug-observability.sh",
            arguments: ["--build-path", buildPath.path, "--skip-build", "--detach"],
            environment: [
                "AGENTSTUDIO_OPEN_BIN": try fixture.executable(
                    "open",
                    """
                    #!/bin/bash
                    echo called > "\(openMarker.path)"
                    exit 0
                    """
                ).path,
                "AGENTSTUDIO_LSOF_BIN": try fixture.executable(
                    "lsof",
                    """
                    #!/bin/bash
                    echo "n\(executablePath)"
                    """
                ).path,
                "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path,
            ]
        )

        #expect(result.exitCode == 1)
        #expect(!FileManager.default.fileExists(atPath: openMarker.path))
        let state = try String(contentsOf: stateFile, encoding: .utf8)
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_STATUS=already_running"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_PID=\(getpid())"))
    }

    @Test("debug launcher ignores stale direct executable state when PID attribution differs")
    func debugLauncherIgnoresStaleDirectExecutableStateWhenPIDAttributionDiffers() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let debugCode = try fixture.worktreeDebugCode()
        let stateFile = fixture.url("latest.env")
        let buildPath = try fixture.makeDebugBuildExecutable(
            """
            #!/bin/bash
            sleep 30
            """
        )
        let executablePath = buildPath.appending(path: "debug/AgentStudio").path
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=\(debugCode)
        AGENTSTUDIO_OBSERVABILITY_LAUNCH_METHOD=direct_executable
        AGENTSTUDIO_OBSERVABILITY_PID=\(getpid())
        AGENTSTUDIO_OBSERVABILITY_EXECUTABLE=\(executablePath)
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)

        let result = try fixture.runScript(
            "scripts/run-debug-observability.sh",
            arguments: ["--build-path", buildPath.path, "--skip-build", "--detach"],
            environment: [
                "AGENTSTUDIO_OPEN_BIN": try fixture.executable(
                    "open",
                    """
                    #!/bin/bash
                    exit 1
                    """
                ).path,
                "AGENTSTUDIO_PGREP_BIN": try fixture.executable(
                    "pgrep",
                    """
                    #!/bin/bash
                    exit 1
                    """
                ).path,
                "AGENTSTUDIO_DITTO_BIN": try fixture.executable(
                    "ditto",
                    """
                    #!/bin/bash
                    cp -R "$1" "$2"
                    """
                ).path,
                "AGENTSTUDIO_CODESIGN_BIN": try fixture.executable(
                    "codesign",
                    """
                    #!/bin/bash
                    exit 0
                    """
                ).path,
                "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path,
                "AGENTSTUDIO_PID_WAIT_ATTEMPTS": "1",
            ]
        )

        #expect(result.exitCode == 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        let state = try String(contentsOf: stateFile, encoding: .utf8)
        defer {
            if let pid = state.firstMatch(of: /AGENTSTUDIO_OBSERVABILITY_PID=([0-9]+)/)?.1 {
                kill(pid_t(pid) ?? -1, SIGTERM)
            }
        }
        #expect(!state.contains("AGENTSTUDIO_OBSERVABILITY_STATUS=already_running"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_STATUS=running"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_LAUNCH_METHOD=direct_executable"))
    }

    @Test("debug launcher overwrites stale state when collector is unhealthy")
    func debugLauncherOverwritesStaleStateWhenCollectorIsUnhealthy() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        let buildPath = try fixture.makeDebugBuildExecutable(
            """
            #!/bin/bash
            sleep 30
            """
        )
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_PID=99999
        AGENTSTUDIO_OBSERVABILITY_MARKER=stale-marker
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)

        let result = try fixture.runScript(
            "scripts/run-debug-observability.sh",
            arguments: ["--build-path", buildPath.path, "--skip-build", "--detach"],
            environment: [
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "curl-unhealthy",
                    """
                    #!/bin/bash
                    exit 22
                    """
                ).path,
                "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path,
            ]
        )

        #expect(result.exitCode == 1)
        let state = try String(contentsOf: stateFile, encoding: .utf8)
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_STATUS=launch_failed"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_REASON=otlp_collector_unhealthy"))
        #expect(!state.contains("stale-marker"))
    }

    @Test("debug launcher falls back to direct executable when local app bundle is blocked")
    func debugLauncherFallsBackToDirectExecutableWhenLaunchServicesBlocksLocalBundle() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        let buildPath = try fixture.makeDebugBuildExecutable(
            """
            #!/bin/bash
            for name in ZMX_DIR ZMX_SESSION ZMX_SESSION_PREFIX GHOSTTY_RESOURCES_DIR GHOSTTY_BIN_DIR __CFBundleIdentifier; do
              if [ -n "${!name:-}" ]; then
                printf "%s leaked\\n" "$name" > "\(fixture.url("leaked-env").path)"
                exit 44
              fi
            done
            printf "data=%s\\n" "$AGENTSTUDIO_DATA_DIR" > "\(fixture.url("launched-env").path)"
            printf "backend=%s\\n" "$AGENTSTUDIO_TRACE_BACKEND" >> "\(fixture.url("launched-env").path)"
            printf "marker=%s\\n" "$AGENTSTUDIO_TRACE_NAME" >> "\(fixture.url("launched-env").path)"
            printf "restore_trace=%s\\n" "${AGENTSTUDIO_RESTORE_TRACE:-}" >> "\(fixture.url("launched-env").path)"
            printf "diagnostic=%s\\n" "${AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION:-}" >> "\(fixture.url("launched-env").path)"
            sleep 30
            """
        )

        let result = try fixture.runScript(
            "scripts/run-debug-observability.sh",
            arguments: ["--build-path", buildPath.path, "--skip-build", "--detach"],
            environment: [
                "AGENTSTUDIO_OPEN_BIN": try fixture.executable(
                    "open",
                    """
                    #!/bin/bash
                    exit 1
                    """
                ).path,
                "AGENTSTUDIO_PGREP_BIN": try fixture.executable(
                    "pgrep",
                    """
                    #!/bin/bash
                    exit 1
                    """
                ).path,
                "AGENTSTUDIO_DITTO_BIN": try fixture.executable(
                    "ditto",
                    """
                    #!/bin/bash
                    cp -R "$1" "$2"
                    """
                ).path,
                "AGENTSTUDIO_CODESIGN_BIN": try fixture.executable(
                    "codesign",
                    """
                    #!/bin/bash
                    exit 0
                    """
                ).path,
                "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path,
                "AGENTSTUDIO_RESTORE_TRACE": "1",
                "AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION": "cross-tab-move-geometry-smoke",
                "ZMX_DIR": "/tmp/hostile-zmx-dir",
                "ZMX_SESSION": "hostile-session",
                "ZMX_SESSION_PREFIX": "hostile-prefix",
                "GHOSTTY_RESOURCES_DIR": "/tmp/hostile-ghostty-resources",
                "GHOSTTY_BIN_DIR": "/tmp/hostile-ghostty-bin",
                "__CFBundleIdentifier": "com.hostile.bundle",
            ]
        )

        #expect(result.exitCode == 0)
        let state = try String(contentsOf: stateFile, encoding: .utf8)
        defer {
            if let pid = state.firstMatch(of: /AGENTSTUDIO_OBSERVABILITY_PID=([0-9]+)/)?.1 {
                kill(pid_t(pid) ?? -1, SIGTERM)
            }
        }
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_STATUS=running"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_LAUNCH_METHOD=direct_executable"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_EXECUTABLE="))
        #expect(state.contains("AgentStudio\\ Debug\\ "))
        #expect(state.contains("/runs/debug-observability-"))
        let buildExecutable = shellEscapedStateValue(buildPath.appending(path: "debug/AgentStudio").path)
        #expect(!state.contains("AGENTSTUDIO_OBSERVABILITY_EXECUTABLE=\(buildExecutable)"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_DATA_DIR="))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_ZMX_DIR="))

        try fixture.waitForFile(
            fixture.url("launched-env"), containing: "diagnostic=cross-tab-move-geometry-smoke", timeoutSeconds: 5)
        let launchedEnv = try String(contentsOf: fixture.url("launched-env"), encoding: .utf8)
        #expect(launchedEnv.contains("data=/"))
        #expect(launchedEnv.contains("/runs/debug-observability-"))
        #expect(launchedEnv.contains("backend=otlp"))
        #expect(launchedEnv.contains("marker=debug-observability-"))
        #expect(launchedEnv.contains("restore_trace=1"))
        #expect(launchedEnv.contains("diagnostic=cross-tab-move-geometry-smoke"))
        #expect(!FileManager.default.fileExists(atPath: fixture.url("leaked-env").path))
    }

    @Test("debug launcher forwards diagnostic env through LaunchServices")
    func debugLauncherForwardsDiagnosticEnvironmentThroughLaunchServices() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        let openArgsURL = fixture.url("open-args")
        let launchedAppURL = fixture.url("launched-app")
        let buildPath = try fixture.makeDebugBuildExecutable(
            """
            #!/bin/bash
            sleep 30
            """
        )

        let result = try fixture.runScript(
            "scripts/run-debug-observability.sh",
            arguments: ["--build-path", buildPath.path, "--skip-build", "--detach"],
            environment: [
                "AGENTSTUDIO_OPEN_BIN": try fixture.executable(
                    "open",
                    """
                    #!/bin/bash
                    printf "%s\\n" "$@" > "\(openArgsURL.path)"
                    for arg in "$@"; do
                      case "$arg" in
                        *.app)
                          printf "%s\\n" "$arg" > "\(launchedAppURL.path)"
                          ;;
                      esac
                    done
                    exit 0
                    """
                ).path,
                "AGENTSTUDIO_PGREP_BIN": try fixture.executable(
                    "pgrep",
                    """
                    #!/bin/bash
                    if [ -f "\(launchedAppURL.path)" ]; then
                      echo 42424
                      exit 0
                    fi
                    exit 1
                    """
                ).path,
                "AGENTSTUDIO_LSOF_BIN": try fixture.executable(
                    "lsof",
                    """
                    #!/bin/bash
                    app_path="$(cat "\(launchedAppURL.path)")"
                    printf "p42424\\nftxt\\nn%s/Contents/MacOS/AgentStudio\\n" "$app_path"
                    """
                ).path,
                "AGENTSTUDIO_DITTO_BIN": try fixture.executable(
                    "ditto",
                    """
                    #!/bin/bash
                    cp -R "$1" "$2"
                    """
                ).path,
                "AGENTSTUDIO_CODESIGN_BIN": try fixture.executable(
                    "codesign",
                    """
                    #!/bin/bash
                    exit 0
                    """
                ).path,
                "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path,
                "AGENTSTUDIO_RESTORE_TRACE": "1",
                "AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION": "cross-tab-move-geometry-smoke",
            ]
        )

        #expect(result.exitCode == 0)
        let state = try String(contentsOf: stateFile, encoding: .utf8)
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_STATUS=running"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_LAUNCH_METHOD=launchservices"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_PID=42424"))
        #expect(state.contains("/runs/debug-observability-"))

        let openArgs = try String(contentsOf: openArgsURL, encoding: .utf8)
        #expect(openArgs.contains("AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=cross-tab-move-geometry-smoke"))
        #expect(openArgs.contains("AGENTSTUDIO_RESTORE_TRACE=1"))
        #expect(openArgs.contains("AGENTSTUDIO_DATA_DIR="))
        #expect(openArgs.contains("/runs/debug-observability-"))
    }

    @Test("debug launcher exposes idle preflight command")
    func debugLauncherExposesIdlePreflightCommand() throws {
        let source = try String(contentsOfFile: "scripts/run-debug-observability.sh", encoding: .utf8)

        #expect(source.contains("run-debug-observability.sh --preflight-idle"))
        #expect(source.contains("preflight_idle=true"))
        #expect(source.contains("running_debug_state_pid \"$state_file\" \"$debug_code\""))
    }

    @Test("debug launcher fails closed when LaunchServices accepts app but PID never appears")
    func debugLauncherFailsClosedWhenLaunchServicesAcceptsAppButPidNeverAppears() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        let launchedEnv = fixture.url("launched-env")
        let buildPath = try fixture.makeDebugBuildExecutable(
            """
            #!/bin/bash
            printf "direct fallback launched\\n" > "\(launchedEnv.path)"
            sleep 30
            """
        )

        let result = try fixture.runScript(
            "scripts/run-debug-observability.sh",
            arguments: ["--build-path", buildPath.path, "--skip-build", "--detach"],
            environment: [
                "AGENTSTUDIO_OPEN_BIN": try fixture.executable(
                    "open",
                    """
                    #!/bin/bash
                    exit 0
                    """
                ).path,
                "AGENTSTUDIO_PGREP_BIN": try fixture.executable(
                    "pgrep",
                    """
                    #!/bin/bash
                    exit 1
                    """
                ).path,
                "AGENTSTUDIO_DITTO_BIN": try fixture.executable(
                    "ditto",
                    """
                    #!/bin/bash
                    cp -R "$1" "$2"
                    """
                ).path,
                "AGENTSTUDIO_CODESIGN_BIN": try fixture.executable(
                    "codesign",
                    """
                    #!/bin/bash
                    exit 0
                    """
                ).path,
                "AGENTSTUDIO_PID_WAIT_ATTEMPTS": "1",
                "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path,
            ]
        )

        #expect(result.exitCode == 1)
        #expect(!FileManager.default.fileExists(atPath: launchedEnv.path))
        let state = try String(contentsOf: stateFile, encoding: .utf8)
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_STATUS=launch_failed"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_REASON=launchservices_pid_not_found"))
    }

    @Test("release scripts do not resolve inject-bundle-version through PATH bash")
    func releaseScriptsUseSystemBashForNestedBundleVersionInjection() throws {
        let miseConfig = try String(contentsOfFile: ".mise.toml", encoding: .utf8)
        let verifierScript = try String(contentsOfFile: "scripts/verify-release-scripts.sh", encoding: .utf8)

        #expect(!miseConfig.contains("\nbash scripts/inject-bundle-version.sh"))
        #expect(miseConfig.contains("/bin/bash scripts/inject-bundle-version.sh"))
        #expect(
            !miseConfig.contains("run = \"bash \\\"$HOME/dev/devfiles/shared/observability/observability-stack\\\""))
        #expect(
            miseConfig.contains(
                "run = \"/bin/bash \\\"$HOME/dev/devfiles/shared/observability/observability-stack\\\" up\""))
        #expect(
            miseConfig.contains(
                "run = \"/bin/bash \\\"$HOME/dev/devfiles/shared/observability/observability-stack\\\" status\""))
        #expect(
            miseConfig.contains(
                "run = \"/bin/bash \\\"$HOME/dev/devfiles/shared/observability/observability-stack\\\" smoke\""))
        #expect(
            miseConfig.contains(
                "run = \"/bin/bash \\\"$HOME/dev/devfiles/shared/observability/observability-stack\\\" down\""))
        #expect(!verifierScript.contains("\nbash \"$ROOT_DIR/scripts/inject-bundle-version.sh\""))
        #expect(verifierScript.contains("/bin/bash \"$ROOT_DIR/scripts/inject-bundle-version.sh\""))
    }
}
