import Foundation
import Testing

@Suite("Observability TCC probe report script")
struct ObservabilityTCCProbeReportScriptTests {
    @Test("report script summarizes marker scoped TCC identity and access rows")
    func reportScriptSummarizesMarkerScopedTCCRows() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR=debug
        AGENTSTUDIO_OBSERVABILITY_MARKER=\(shellEscapedStateValue("debug marker | fields process.pid"))
        AGENTSTUDIO_OBSERVABILITY_PROOF_TOKEN=\(shellEscapedStateValue("proof token | fields process.pid"))
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION=tcc-upgrade-probe
        """.write(to: stateFile, atomically: true, encoding: .utf8)
        let curlArguments = fixture.url("curl-arguments")

        let result = try fixture.runScript(
            "scripts/report-tcc-upgrade-probe-observability.sh",
            arguments: ["--state-file", stateFile.path],
            environment: [
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "tcc-report-curl",
                    """
                    #!/bin/bash
                    printf '%s\\n' "$*" >> "\(curlArguments.path)"
                    if [[ "$*" == *"terminal.tcc.app_identity_snapshot"* ]]; then
                      printf '{"_msg":"terminal.tcc.app_identity_snapshot","agentstudio.tcc.probe.sequence":0,"agentstudio.tcc.bundle.kind":"debug","agentstudio.tcc.code_identity.kind":"same_disk_identity","agentstudio.tcc.bundle.changed":false,"agentstudio.tcc.bundle.executable.reachable":true}\\n'
                      printf '{"_msg":"terminal.tcc.app_identity_snapshot","agentstudio.tcc.probe.sequence":1,"agentstudio.tcc.bundle.kind":"debug","agentstudio.tcc.code_identity.kind":"different_disk_identity","agentstudio.tcc.bundle.changed":true,"agentstudio.tcc.bundle.executable.reachable":true}\\n'
                      exit 0
                    fi
                    if [[ "$*" == *"terminal.tcc.access_probe"* ]]; then
                      printf '{"_msg":"terminal.tcc.access_probe","agentstudio.tcc.probe.sequence":0,"agentstudio.tcc.subject":"shell_child","agentstudio.tcc.access.target":"documents","agentstudio.tcc.access.result":"granted","agentstudio.tcc.responsible.kind":"agentstudio_debug","agentstudio.tcc.command.exit_class":"ok"}\\n'
                      printf '{"_msg":"terminal.tcc.access_probe","agentstudio.tcc.probe.sequence":1,"agentstudio.tcc.subject":"shell_child","agentstudio.tcc.access.target":"documents","agentstudio.tcc.access.result":"denied_eacces","agentstudio.tcc.responsible.kind":"agentstudio_debug","agentstudio.tcc.command.exit_class":"permission_denied"}\\n'
                      exit 0
                    fi
                    exit 0
                    """
                ).path
            ]
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("identity discontinuity observed: true"))
        #expect(result.stdout.contains("access denied observed: true"))
        #expect(result.stdout.contains("different_disk_identity"))
        #expect(result.stdout.contains("denied_eacces"))
        let curlArgumentText = try String(contentsOf: curlArguments, encoding: .utf8)
        #expect(curlArgumentText.contains("agent.proof.marker:=\"debug marker | fields process.pid\""))
        #expect(curlArgumentText.contains("agent.proof.launch:=\"proof token | fields process.pid\""))
        #expect(curlArgumentText.contains("_msg:=\"terminal.tcc.app_identity_snapshot\""))
        #expect(curlArgumentText.contains("_msg:=\"terminal.tcc.access_probe\""))
    }

    @Test("report script can require identity discontinuity")
    func reportScriptCanRequireIdentityDiscontinuity() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR=debug
        AGENTSTUDIO_OBSERVABILITY_MARKER=debug-marker
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION=tcc-upgrade-probe
        """.write(to: stateFile, atomically: true, encoding: .utf8)

        let result = try fixture.runScript(
            "scripts/report-tcc-upgrade-probe-observability.sh",
            arguments: ["--state-file", stateFile.path, "--require-identity-discontinuity"],
            environment: [
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "tcc-report-curl",
                    """
                    #!/bin/bash
                    if [[ "$*" == *"terminal.tcc.app_identity_snapshot"* ]]; then
                      printf '{"_msg":"terminal.tcc.app_identity_snapshot","agentstudio.tcc.probe.sequence":0,"agentstudio.tcc.bundle.kind":"debug","agentstudio.tcc.code_identity.kind":"same_disk_identity","agentstudio.tcc.bundle.changed":false,"agentstudio.tcc.bundle.executable.reachable":true}\\n'
                      exit 0
                    fi
                    if [[ "$*" == *"terminal.tcc.access_probe"* ]]; then
                      printf '{"_msg":"terminal.tcc.access_probe","agentstudio.tcc.probe.sequence":0,"agentstudio.tcc.subject":"shell_child","agentstudio.tcc.access.target":"documents","agentstudio.tcc.access.result":"granted","agentstudio.tcc.responsible.kind":"agentstudio_debug","agentstudio.tcc.command.exit_class":"ok"}\\n'
                      exit 0
                    fi
                    exit 0
                    """
                ).path
            ]
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("identity discontinuity was required but not observed"))
    }
}
