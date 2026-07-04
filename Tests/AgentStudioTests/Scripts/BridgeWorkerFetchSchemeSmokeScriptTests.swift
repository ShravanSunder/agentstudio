import Foundation
import Testing

@Suite("Bridge worker fetch scheme smoke verifier script")
struct BridgeWorkerFetchSchemeSmokeScriptTests {
    @Test("worker fetch scheme smoke verifier requires worker fetch marker and byte observation")
    func verifierRequiresWorkerFetchMarkerAndByteObservation() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=debug-marker
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=testcode
        AGENTSTUDIO_OBSERVABILITY_PID=999999999
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION=bridge-worker-fetch-scheme-smoke
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)

        let result = try fixture.runScript(
            "scripts/verify-bridge-worker-fetch-scheme-smoke.sh",
            arguments: ["--dry-run"],
            environment: [
                "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path,
                "AGENTSTUDIO_OBSERVABILITY_VERIFY_ATTEMPTS": "1",
                "AGENTSTUDIO_OBSERVABILITY_VERIFY_RETRY_DELAY_SECONDS": "0",
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "curl-worker-fetch-missing-marker",
                    """
                    #!/bin/bash
                    exit 0
                    """
                ).path,
            ]
        )

        #expect(result.exitCode == 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        #expect(result.stdout.contains("requires worker fetch marker and byte observation"))
    }

    @Test("worker fetch scheme smoke verifier reports blocked failure reason")
    func verifierReportsBlockedFailureReason() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=debug-marker
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=testcode
        AGENTSTUDIO_OBSERVABILITY_PID=999999999
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION=bridge-worker-fetch-scheme-smoke
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)

        let result = try fixture.runScript(
            "scripts/verify-bridge-worker-fetch-scheme-smoke.sh",
            arguments: [],
            environment: [
                "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path,
                "AGENTSTUDIO_OBSERVABILITY_VERIFY_ATTEMPTS": "1",
                "AGENTSTUDIO_OBSERVABILITY_VERIFY_RETRY_DELAY_SECONDS": "0",
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "curl-worker-fetch-blocked",
                    """
                    #!/bin/bash
                    args="$*"
                    if [[ "$args" == *"app.startup_diagnostic_action.blocked"* ]]; then
                      printf '%s\\n' '{"_msg":"app.startup_diagnostic_action.blocked","agentstudio.startup_diagnostic.bridge.worker_fetch.failure.reason":"javascript_probe_failed","agentstudio.startup_diagnostic.bridge.worker_fetch.fetch.succeeded":false,"agentstudio.startup_diagnostic.bridge.worker_fetch.stream.succeeded":false,"agentstudio.startup_diagnostic.bridge.worker_fetch.worker_observed_byte.count":0,"agentstudio.startup_diagnostic.bridge.worker_fetch.stream_first_chunk_byte.count":0}'
                    fi
                    exit 0
                    """
                ).path,
            ]
        )

        #expect(result.exitCode == 1, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        #expect(result.stderr.contains("javascript_probe_failed"))
        #expect(result.stderr.contains("fetch.succeeded=false"))
        #expect(result.stderr.contains("stream.succeeded=false"))
    }

    @Test("worker fetch scheme smoke verifier is wired through mise")
    func verifierIsWiredThroughMise() throws {
        let miseConfig = try String(contentsOfFile: ".mise.toml", encoding: .utf8)

        #expect(miseConfig.contains("[tasks.verify-bridge-worker-fetch-scheme-smoke]"))
        #expect(miseConfig.contains("scripts/verify-bridge-worker-fetch-scheme-smoke.sh"))
    }
}
