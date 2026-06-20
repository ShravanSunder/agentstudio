import Foundation
import Testing

@Suite("Observability debug zmx isolation")
struct ObservabilityDebugLaunchZmxIsolationTests {
    @Test("debug launcher fails closed when bundled zmx is missing")
    func debugLauncherFailsClosedWhenBundledZmxIsMissing() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        let openMarker = fixture.url("open-called")
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
                    echo called > "\(openMarker.path)"
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
                    "ditto-skip-zmx",
                    """
                    #!/bin/bash
                    case "$1" in
                      *vendor/zmx/zig-out/bin/zmx)
                        exit 0
                        ;;
                    esac
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

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("debug app bundle missing executable zmx"))
        #expect(!FileManager.default.fileExists(atPath: openMarker.path))
        let state = try String(contentsOf: stateFile, encoding: .utf8)
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_STATUS=launch_failed"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_REASON=missing_debug_zmx_binary"))
    }
}
