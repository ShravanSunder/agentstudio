import Foundation
import Testing

@Suite("Observability TCC replacement experiment script")
struct ObservabilityTCCReplacementExperimentScriptTests {
    @Test("replacement experiment dry run accepts generated debug app state")
    func replacementExperimentDryRunAcceptsGeneratedDebugAppState() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let debugCode = "tcc1"
        let fakeHome = fixture.url("home")
        let debugRoot =
            fakeHome
            .appending(path: ".agentstudio-db")
            .appending(path: debugCode)
        let app =
            debugRoot
            .appending(path: "apps")
            .appending(path: "app-test")
            .appending(path: "AgentStudio Debug \(debugCode).app")
        let appExecutable = app.appending(path: "Contents/MacOS/AgentStudio")
        let replacementExecutable = fixture.url("replacement-AgentStudio")
        try FileManager.default.createDirectory(
            at: appExecutable.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try "#!/bin/bash\nexit 0\n".write(to: appExecutable, atomically: true, encoding: .utf8)
        try "#!/bin/bash\nexit 0\n".write(to: replacementExecutable, atomically: true, encoding: .utf8)
        chmod(appExecutable.path, 0o755)
        chmod(replacementExecutable.path, 0o755)
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR=debug
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=\(debugCode)
        AGENTSTUDIO_OBSERVABILITY_APP=\(shellEscapedStateValue(app.path))
        AGENTSTUDIO_OBSERVABILITY_EXECUTABLE=\(shellEscapedStateValue(appExecutable.path))
        AGENTSTUDIO_OBSERVABILITY_BUILD_PATH=\(shellEscapedStateValue(fixture.root.path))
        AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION=tcc-upgrade-probe
        """.write(to: stateFile, atomically: true, encoding: .utf8)

        let result = try fixture.runScript(
            "scripts/replace-running-debug-app-for-tcc-probe.sh",
            arguments: [
                "--state-file", stateFile.path,
                "--replacement-executable", replacementExecutable.path,
                "--dry-run",
            ],
            environment: [
                "HOME": fakeHome.path,
                "AGENTSTUDIO_DITTO_BIN": try fixture.executable(
                    "replacement-ditto",
                    """
                    #!/bin/bash
                    echo "ditto should not run in dry-run" >&2
                    exit 99
                    """
                ).path,
            ]
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("dry run: no files mutated"))
        #expect(result.stdout.contains("AgentStudio Debug \(debugCode).app"))
    }

    @Test("replacement experiment refuses non debug runtime")
    func replacementExperimentRefusesNonDebugRuntime() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR=beta
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=tcc1
        AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION=tcc-upgrade-probe
        """.write(to: stateFile, atomically: true, encoding: .utf8)

        let result = try fixture.runScript(
            "scripts/replace-running-debug-app-for-tcc-probe.sh",
            arguments: ["--state-file", stateFile.path, "--dry-run"],
            environment: [:]
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("refusing to mutate non-debug observability runtime"))
    }

    @Test("replacement experiment refuses app outside generated debug root")
    func replacementExperimentRefusesAppOutsideGeneratedDebugRoot() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let fakeHome = fixture.url("home")
        let app = fixture.url("AgentStudio Debug tcc1.app")
        let appExecutable = app.appending(path: "Contents/MacOS/AgentStudio")
        let replacementExecutable = fixture.url("replacement-AgentStudio")
        try FileManager.default.createDirectory(
            at: appExecutable.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try "#!/bin/bash\nexit 0\n".write(to: appExecutable, atomically: true, encoding: .utf8)
        try "#!/bin/bash\nexit 0\n".write(to: replacementExecutable, atomically: true, encoding: .utf8)
        chmod(appExecutable.path, 0o755)
        chmod(replacementExecutable.path, 0o755)
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR=debug
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=tcc1
        AGENTSTUDIO_OBSERVABILITY_APP=\(shellEscapedStateValue(app.path))
        AGENTSTUDIO_OBSERVABILITY_EXECUTABLE=\(shellEscapedStateValue(appExecutable.path))
        AGENTSTUDIO_OBSERVABILITY_BUILD_PATH=\(shellEscapedStateValue(fixture.root.path))
        AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION=tcc-upgrade-probe
        """.write(to: stateFile, atomically: true, encoding: .utf8)

        let result = try fixture.runScript(
            "scripts/replace-running-debug-app-for-tcc-probe.sh",
            arguments: [
                "--state-file", stateFile.path,
                "--replacement-executable", replacementExecutable.path,
                "--dry-run",
            ],
            environment: [
                "HOME": fakeHome.path
            ]
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("refusing to mutate app outside generated debug app root"))
    }
}
