import Darwin
import Foundation
import Testing

@Suite("Observability debug candidate lifecycle scripts")
struct ObservabilityDebugCandidateLifecycleScriptTests {
    @Test("candidate retirement signals only the exact current debug launch identity")
    func candidateRetirementSignalsOnlyExactCurrentDebugIdentity() throws {
        let outcome = try runCandidateRetirementContract(actualIdentityOverrides: [:])

        #expect(outcome.result.exitCode == 0, "stdout: \(outcome.result.stdout)\nstderr: \(outcome.result.stderr)")
        #expect(outcome.signalArguments.contains("4242"))
        #expect(outcome.result.stdout.contains("candidate_retirement=signalled"))
    }

    @Test("candidate retirement treats an absent process as already retired")
    func candidateRetirementDoesNotSignalAbsentProcess() throws {
        let outcome = try runCandidateRetirementContract(
            actualIdentityOverrides: ["present": false]
        )

        #expect(outcome.result.exitCode == 0, "stdout: \(outcome.result.stdout)\nstderr: \(outcome.result.stderr)")
        #expect(outcome.signalArguments.isEmpty)
        #expect(outcome.result.stdout.contains("candidate_retirement=absent"))
    }

    @Test("candidate retirement refuses stale reused or mismatched identity")
    func candidateRetirementRefusesEveryIdentityMismatch() throws {
        let mismatches: [[String: Any]] = [
            ["pid": 5252],
            ["executable": "/tmp/unrelated/AgentStudio"],
            ["debug_code": "nope"],
            ["marker": "stale-marker"],
            ["process_start_identity": "different-start"],
            ["bundle_identifier": "com.agentstudio.app", "runtime_flavor": "stable"],
            ["bundle_identifier": "com.agentstudio.app.beta", "runtime_flavor": "beta"],
        ]

        for mismatch in mismatches {
            let outcome = try runCandidateRetirementContract(actualIdentityOverrides: mismatch)
            #expect(outcome.result.exitCode == 1, "stdout: \(outcome.result.stdout)")
            #expect(outcome.signalArguments.isEmpty)
            #expect(outcome.result.stderr.contains("candidate identity mismatch"))
        }
    }

    @Test("debug zmx helper inventories only one validated exact debug root")
    func debugZmxHelperInventoriesOnlyOneValidatedExactRoot() throws {
        for listing in [
            "",
            "name=session-1\\tclients=1\\tstart_dir=/tmp/worktree\\n",
        ] {
            let fixture = try LauncherScriptFixture()
            defer { fixture.cleanup() }
            let exactRoot = fixture.url(".agentstudio-db/test/z")
            try FileManager.default.createDirectory(at: exactRoot, withIntermediateDirectories: true)
            let zmxPath = fixture.url(".agentstudio-db/test/bin/zmx")
            try FileManager.default.createDirectory(
                at: zmxPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let zmx = try fixture.executable(
                ".agentstudio-db/test/bin/zmx",
                """
                #!/bin/bash
                if [ "${1:-}" = "list" ]; then
                  printf '%b' "\(listing)"
                  exit 0
                fi
                exit 70
                """
            )

            let result = try fixture.runScript(
                "scripts/cleanup-debug-zmx-sessions.sh",
                arguments: ["--inventory-exact-root", exactRoot.path, "--zmx-bin", zmx.path],
                environment: [:]
            )

            #expect(result.exitCode == 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
            #expect(result.stdout.contains(".agentstudio-db/test/z status=ok"))
            #expect(!result.stdout.contains("zmx kill"))
        }
    }

    @Test("debug zmx exact-root inventory fails closed on list error and protected roots")
    func debugZmxExactRootInventoryRejectsListFailureAndProtectedRoots() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let zmx = try fixture.executable(
            "zmx-list-failure",
            """
            #!/bin/bash
            exit 71
            """
        )
        let exactRoot = fixture.url(".agentstudio-db/test/z")
        try FileManager.default.createDirectory(at: exactRoot, withIntermediateDirectories: true)
        let exactZmxPath = fixture.url(".agentstudio-db/test/bin/zmx")
        try FileManager.default.createDirectory(
            at: exactZmxPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: zmx, to: exactZmxPath)
        chmod(exactZmxPath.path, 0o755)
        let listFailure = try fixture.runScript(
            "scripts/cleanup-debug-zmx-sessions.sh",
            arguments: ["--inventory-exact-root", exactRoot.path, "--zmx-bin", exactZmxPath.path],
            environment: [:]
        )
        #expect(listFailure.exitCode == 1)
        #expect(listFailure.stderr.contains("status=list_failed"))

        for protectedRoot in [fixture.url(".agentstudio/z"), fixture.url(".agent-studio-b/z")] {
            try FileManager.default.createDirectory(at: protectedRoot, withIntermediateDirectories: true)
            let result = try fixture.runScript(
                "scripts/cleanup-debug-zmx-sessions.sh",
                arguments: ["--inventory-exact-root", protectedRoot.path, "--zmx-bin", zmx.path],
                environment: [:]
            )
            #expect(result.exitCode == 2)
            #expect(result.stderr.contains("outside isolated debug root"))
        }
    }

    @Test("sidebar performance proof uses exact-root inventory and launcher retirement only")
    func sidebarPerformanceProofAvoidsBroadCleanupAndBarePIDSignals() throws {
        let source = try String(
            contentsOfFile: "scripts/verify-sidebar-performance-workload.sh",
            encoding: .utf8
        )

        #expect(source.contains("--inventory-exact-root"))
        #expect(source.contains("--retire-candidate"))
        #expect(!source.contains("cleanup-debug-zmx-sessions.sh\" --dry-run"))
        #expect(!source.contains("cleanup-debug-zmx-sessions.sh\" --execute"))
        #expect(!source.contains("stop_pid \"$APP_PID\""))
        #expect(source.contains("wait \"$ZMX_MONITOR_PID\""))
    }

    private func runCandidateRetirementContract(
        actualIdentityOverrides: [String: Any]
    ) throws -> (result: ScriptRunResult, signalArguments: String) {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let debugCode = try fixture.worktreeDebugCode()
        let app = try fixture.makeAppBundle(
            name: ".agentstudio-db/\(debugCode)/apps/AgentStudio Debug \(debugCode).app",
            releaseChannel: "stable",
            bundleIdentifier: "com.agentstudio.app.debug.d\(debugCode)"
        )
        let executable = app.appending(path: "Contents/MacOS/AgentStudio")
        let stateFile = fixture.url("candidate.env")
        let signalFile = fixture.url("signal-arguments")
        let marker = "strict-cpu-candidate"
        let startIdentity = "kernel-start-4242"
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR=debug
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=\(debugCode)
        AGENTSTUDIO_OBSERVABILITY_MARKER=\(marker)
        AGENTSTUDIO_OBSERVABILITY_PID=4242
        AGENTSTUDIO_OBSERVABILITY_PROCESS_START_IDENTITY=\(startIdentity)
        AGENTSTUDIO_OBSERVABILITY_BUNDLE_IDENTIFIER=com.agentstudio.app.debug.d\(debugCode)
        AGENTSTUDIO_OBSERVABILITY_APP=\(shellEscapedStateValue(app.path))
        AGENTSTUDIO_OBSERVABILITY_EXECUTABLE=\(shellEscapedStateValue(executable.path))
        AGENTSTUDIO_OBSERVABILITY_DATA_DIR=\(fixture.url(".agentstudio-db/\(debugCode)").path)
        AGENTSTUDIO_OBSERVABILITY_ZMX_DIR=\(fixture.url(".agentstudio-db/\(debugCode)/z").path)
        """.appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)

        var actualIdentity: [String: Any] = [
            "present": true,
            "pid": 4242,
            "runtime_flavor": "debug",
            "debug_code": debugCode,
            "marker": marker,
            "process_start_identity": startIdentity,
            "bundle_identifier": "com.agentstudio.app.debug.d\(debugCode)",
            "app": app.path,
            "executable": executable.path,
            "data_dir": fixture.url(".agentstudio-db/\(debugCode)").path,
            "zmx_dir": fixture.url(".agentstudio-db/\(debugCode)/z").path,
        ]
        for (key, value) in actualIdentityOverrides {
            actualIdentity[key] = value
        }
        let identityData = try JSONSerialization.data(withJSONObject: actualIdentity, options: [.sortedKeys])
        let identityJSON = try #require(String(data: identityData, encoding: .utf8))
        let signal = try fixture.executable(
            "signal",
            """
            #!/bin/bash
            printf '%s\\n' "$*" >> "\(signalFile.path)"
            """
        )

        let result = try fixture.runScript(
            "scripts/run-debug-observability.sh",
            arguments: ["--retire-candidate"],
            environment: [
                "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path,
                "AGENTSTUDIO_OBSERVABILITY_TEST_CANDIDATE_IDENTITY": identityJSON,
                "AGENTSTUDIO_SIGNAL_BIN": signal.path,
            ]
        )
        let signalArguments =
            (try? String(contentsOf: signalFile, encoding: .utf8)) ?? ""
        return (result, signalArguments)
    }
}
