import Foundation
import Testing

@Suite("Observability beta launcher duplicate runtime scripts")
struct ObservabilityBetaLauncherDuplicateRuntimeTests {
    @Test("beta launcher refuses running beta from a different bundle path")
    func betaLauncherRefusesAnyRunningBetaRuntime() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let selectedApp = try fixture.makeAppBundle(name: "Selected AgentStudio Beta.app", releaseChannel: "beta")
        let runningApp = try fixture.makeAppBundle(name: "Installed AgentStudio Beta.app", releaseChannel: "beta")
        let openMarker = fixture.url("open-called")
        let stateFile = fixture.url("latest.env")

        let result = try fixture.runScript(
            "scripts/run-beta-observability.sh",
            arguments: ["--app", selectedApp.path, "--detach"],
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
                    echo 4242
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

        #expect(result.exitCode == 1)
        #expect(!FileManager.default.fileExists(atPath: openMarker.path))
        let state = try String(contentsOf: stateFile, encoding: .utf8)
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_STATUS=already_running"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_PID=4242"))
    }

    @Test("beta launcher fails closed when running process attribution is unavailable")
    func betaLauncherFailsClosedWhenRunningProcessAttributionIsUnavailable() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let selectedApp = try fixture.makeAppBundle(name: "Selected AgentStudio Beta.app", releaseChannel: "beta")
        let stateFile = fixture.url("latest.env")

        let result = try fixture.runScript(
            "scripts/run-beta-observability.sh",
            arguments: ["--app", selectedApp.path, "--detach"],
            environment: [
                "AGENTSTUDIO_PGREP_BIN": try fixture.executable(
                    "pgrep",
                    """
                    #!/bin/bash
                    echo 4343
                    """
                ).path,
                "AGENTSTUDIO_LSOF_BIN": try fixture.executable(
                    "lsof",
                    """
                    #!/bin/bash
                    exit 0
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
}
