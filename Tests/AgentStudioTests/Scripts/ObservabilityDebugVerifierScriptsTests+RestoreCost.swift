import Darwin
import Foundation
import Testing

extension ObservabilityDebugVerifierScriptsTests {
    @Test(
        "restore cost verification refuses every missing phase instead of treating absence as zero",
        arguments: [
            "performance.restore.foreground.gather", "performance.restore.foreground.schedule",
            "performance.restore.foreground.probe", "performance.restore.foreground.watch",
            "performance.restore.resume.decide",
        ])
    func restoreCostVerifierRefusesMissingPhase(missingPhase: String) async throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let app = try fixture.makeAppBundle(
            name: "Agent Studio Debug testcode.app", releaseChannel: "stable",
            bundleIdentifier: "com.agentstudio.app.debug.dtestcode")
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=restore-cost-contract
        AGENTSTUDIO_OBSERVABILITY_PROOF_TOKEN=restore-cost-launch
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=testcode
        AGENTSTUDIO_OBSERVABILITY_PID=\(getpid())
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-10-02T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_APP=\(shellEscapedStateValue(app.path))
        """.write(to: stateFile, atomically: true, encoding: .utf8)
        let queryLog = fixture.url("queries.txt")
        let curl = try fixture.executable(
            "curl",
            """
            #!/bin/bash
            printf '%s\\n' "$*" >> "\(queryLog.path)"
            # The fixture supplies complete startup/safety data and all phases
            # except the parameterized omission. No real endpoint is contacted.
            if [[ "$*" == *"\(missingPhase)"* ]]; then
              if [[ "$*" == *"api/v1/query"* ]]; then
                printf '{"status":"success","data":{"resultType":"vector","result":[]}}\\n'
              fi
              exit 0
            fi
            if [[ "$*" == *"api/v1/query"* ]]; then
              value=1
              [[ "$*" == *"main_thread"* ]] && value=0
              [[ "$*" == *"live_pane"* ]] && value=18
              printf '{"status":"success","data":{"resultType":"vector","result":[{"metric":{},"value":[1,"%s"]}]}}\\n' "$value"
              exit 0
            fi
            if [[ "$*" == *"app.did_finish_launching.succeeded"* ]]; then
              printf '{"_msg":"app.did_finish_launching.succeeded","agentstudio.app.startup.phase":"did_finish_launching","agentstudio.app.startup.outcome":"succeeded"}\\n'
              exit 0
            fi
            if [[ "$*" == *":*"* ]]; then exit 0; fi
            if [[ "$*" == *"performance.restore"* ]]; then
              for phase in performance.restore.foreground.gather performance.restore.foreground.schedule \
                           performance.restore.foreground.probe performance.restore.foreground.watch performance.restore.resume.decide; do
                [[ "$phase" == "\(missingPhase)" ]] && continue
                [[ "$*" == *"$phase"* || "$*" != *"performance.restore."* ]] || continue
                printf '{"_msg":"%s","agentstudio.performance.restore.execution.count":1,"agentstudio.performance.elapsed_ms":1,"agentstudio.performance.restore.main_thread.execution.count":0,"agentstudio.performance.restore.main_thread.elapsed_ms":0,"agentstudio.performance.restore.live_pane.count":18,"agentstudio.performance.restore.workload.closed":true}\\n' "$phase"
              done
              exit 0
            fi
            printf '{"service.name":"AgentStudio","service.version":"0.0.1-debug+abcd1234","dev.runtime.flavor":"debug","_msg":"app.process.start"}\\n'
            """
        )
        let lsof = try fixture.executable("lsof", "#!/bin/bash\necho 'n\(app.path)/Contents/MacOS/AgentStudio'\n")
        let result = try await fixture.runVerifier(
            scriptPath: "scripts/verify-debug-observability.sh", stateFile: stateFile,
            environment: [
                "AGENTSTUDIO_CURL_BIN": curl.path, "AGENTSTUDIO_LSOF_BIN": lsof.path,
                "AGENTSTUDIO_RESTORE_R3_COST_PROOF": "1",
            ])
        #expect(result.exitCode != 0, "a missing phase must fail, stdout: \(result.stdout)")
        #expect(result.stderr.contains("missing restore phase \(missingPhase)"))
        let queries = try String(contentsOf: queryLog, encoding: .utf8)
        #expect(queries.contains(missingPhase))
        #expect(queries.contains("agent.proof.marker:=\"restore-cost-contract\""))
        #expect(queries.contains("agent.proof.launch:=\"restore-cost-launch\""))
    }
}
