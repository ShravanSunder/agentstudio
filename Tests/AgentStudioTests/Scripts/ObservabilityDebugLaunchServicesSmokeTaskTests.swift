import Darwin
import Foundation
import Testing

@Suite("Observability debug LaunchServices smoke task")
struct ObservabilityDebugLaunchServicesSmokeTaskTests {
    @Test("debug verifier strict LaunchServices mode rejects direct executable fallback before logs")
    func debugVerifierStrictLaunchServicesModeRejectsDirectExecutableFallbackBeforeLogs() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        let curlMarker = fixture.url("curl-called")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=debug-marker
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=testcode
        AGENTSTUDIO_OBSERVABILITY_PID=\(getpid())
        AGENTSTUDIO_OBSERVABILITY_LAUNCH_METHOD=direct_executable
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)

        let result = try fixture.runVerifier(
            scriptPath: "scripts/verify-debug-observability.sh",
            stateFile: stateFile,
            environment: [
                "AGENTSTUDIO_REQUIRE_LAUNCHSERVICES": "1",
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "curl",
                    """
                    #!/bin/bash
                    echo called > "\(curlMarker.path)"
                    exit 0
                    """
                ).path,
            ]
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("requires LaunchServices"))
        #expect(!FileManager.default.fileExists(atPath: curlMarker.path))
    }

    @Test("mise exposes strict debug LaunchServices smoke task")
    func miseExposesStrictDebugLaunchServicesSmokeTask() throws {
        let source = try String(contentsOfFile: ".mise.toml", encoding: .utf8)

        #expect(source.contains("[tasks.smoke-debug-launchservices]"))
        #expect(source.contains("/bin/bash scripts/run-debug-observability.sh --detach"))
        #expect(
            source.contains(
                "AGENTSTUDIO_REQUIRE_LAUNCHSERVICES=1 /bin/bash scripts/verify-debug-observability.sh"))
    }
}
