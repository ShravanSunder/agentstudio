import Darwin
import Foundation
import Testing

@Suite("Observability launch scripts")
struct ObservabilityLaunchScriptsTests {
    @Test("debug launcher creates isolated per-worktree app identity")
    func debugLauncherCreatesIsolatedPerWorktreeAppIdentity() throws {
        let script = try String(contentsOfFile: "scripts/run-debug-observability.sh", encoding: .utf8)

        #expect(script.contains("worktree_debug_code()"))
        #expect(script.contains("space = 36 ** 4"))
        #expect(script.contains("source \"$PROJECT_ROOT/scripts/swift-build-slot.sh\" debug"))
        #expect(script.contains("--print-identity"))
        #expect(script.contains("AgentStudio Debug $code.app"))
        #expect(script.contains("Agent Studio Debug $code"))
        #expect(script.contains("com.agentstudio.app.debug.d$code"))
        #expect(script.contains("Delete :CFBundleURLTypes"))
        #expect(!script.contains("CFBundleURLTypes:0:CFBundleURLSchemes:0 \"agentstudio\""))
        #expect(script.contains("debug_root=\"$HOME/.agentstudio-db/$debug_code\""))
        #expect(script.contains("trace_name_is_safe_path_component()"))
        #expect(script.contains("write_launch_failed_state invalid_trace_name"))
        #expect(script.contains("launch_data_root=\"${AGENTSTUDIO_DEBUG_DATA_DIR:-$debug_root}\""))
        #expect(script.contains("launch_data_root=\"$debug_root/runs/$trace_name\""))
        #expect(script.contains("\"AGENTSTUDIO_DATA_DIR=$launch_data_root\""))
        #expect(script.contains("AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION"))
        #expect(script.contains("AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE"))
        #expect(script.contains("running_debug_app_pids()"))
        #expect(script.contains("Agent Studio Debug $debug_code is already running"))
        #expect(script.contains("AGENTSTUDIO_OBSERVABILITY_STATUS already_running"))
    }

    @Test("debug worktree code avoids known four character collision")
    func debugWorktreeCodeAvoidsKnownFourCharacterCollision() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }

        let firstCode = try fixture.worktreeDebugCode(for: "/tmp/worktree-657")
        let secondCode = try fixture.worktreeDebugCode(for: "/tmp/worktree-1190")

        #expect(firstCode.count == 4)
        #expect(secondCode.count == 4)
        #expect(firstCode != secondCode)
    }

    @Test("mise swift test tasks forward requested filters through the slot wrapper")
    func miseSwiftTestTasksForwardRequestedFiltersThroughSlotWrapper() throws {
        let miseConfig = try String(contentsOfFile: ".mise.toml", encoding: .utf8)
        let wrapperScript = try String(contentsOfFile: "scripts/run-swift-test-task.sh", encoding: .utf8)
        let testHelperScript = try String(contentsOfFile: "scripts/swift-test-helpers.sh", encoding: .utf8)
        let agentInstructions = try String(contentsOfFile: "AGENTS.md", encoding: .utf8)
        let ciWorkflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)

        #expect(miseConfig.contains("run = \"/bin/bash scripts/run-swift-test-task.sh test\""))
        #expect(miseConfig.contains("run = \"/bin/bash scripts/run-swift-test-task.sh test-fast\""))
        #expect(miseConfig.contains("run = \"/bin/bash scripts/run-swift-test-task.sh test-prebuild\""))
        #expect(miseConfig.contains("run = \"/bin/bash scripts/run-swift-test-task.sh test-webkit\""))
        #expect(miseConfig.contains("[tasks.test-e2e]"))
        #expect(miseConfig.contains("[tasks.test-zmx-e2e]"))
        #expect(miseConfig.contains("source \"${PROJECT_ROOT}/scripts/swift-build-slot.sh\" debug"))
        #expect(wrapperScript.contains("source \"${PROJECT_ROOT}/scripts/swift-build-slot.sh\" debug"))
        #expect(wrapperScript.contains("TIMEOUT_SECONDS=\"${SWIFT_TEST_TIMEOUT_SECONDS:-60}\""))
        #expect(wrapperScript.contains("SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS:-$TIMEOUT_SECONDS"))
        #expect(wrapperScript.contains("SWIFT_TEST_SKIP_PREBUILD"))
        #expect(wrapperScript.contains("PREBUILD_TIMEOUT_SECONDS=$PREBUILD_TIMEOUT_SECONDS"))
        #expect(wrapperScript.contains("run_swift_with_timeout"))
        #expect(wrapperScript.contains("requested swift test args: $*"))
        #expect(wrapperScript.contains("requested_args_include_serialized_suite_filter()"))
        #expect(wrapperScript.contains("--skip WebKitSerializedTests"))
        #expect(wrapperScript.contains("--skip E2ESerializedTests"))
        #expect(wrapperScript.contains("--skip ZmxE2ETests"))
        #expect(wrapperScript.contains("swift_test_args=(\"$@\")"))
        #expect(wrapperScript.contains("swift_test_args+=("))
        #expect(wrapperScript.contains("swift test --skip-build \"${swift_test_args[@]}\""))
        #expect(wrapperScript.contains("AGENTSTUDIO_TRACE_BACKEND=\"${SWIFT_TEST_TRACE_BACKEND:-jsonl}\""))
        #expect(testHelperScript.contains("Timeout in seconds for the one-time test bundle build"))
        #expect(testHelperScript.contains("\"prebuild test bundles\" \\\n    \"$PREBUILD_TIMEOUT_SECONDS\""))
        #expect(testHelperScript.contains("swift_test_output_has_failures()"))
        #expect(testHelperScript.contains("emitted Swift Testing failure output despite exit 0"))
        #expect(testHelperScript.contains("recorded an issue"))
        #expect(testHelperScript.contains("grep -Eq \"unexpected signal code [0-9]+\" <<<\"$output\""))
        #expect(!testHelperScript.contains("echo \"$output\" | grep -Eq \"unexpected signal code [0-9]+\""))
        #expect(
            testHelperScript.contains(
                "WebKitSerializedTests/BridgeTransportIntegrationTests/test_pushPackageMetadata_rendersReviewViewerShell"
            ))
        #expect(testHelperScript.contains("WebKitSerializedTests/BridgePaneControllerIPCProjectionTests"))
        #expect(testHelperScript.contains("WebKitSerializedTests/BridgePaneControllerContentAuthorityTests"))
        #expect(!testHelperScript.contains("\nWebKitSerializedTests/BridgeTransportIntegrationTests\n"))
        #expect(testHelperScript.contains("terminate_process_tree TERM \"$command_pid\""))
        #expect(!testHelperScript.contains("pkill -9 -f"))
        #expect(!agentInstructions.contains("pkill -f \"swift-build\""))
        #expect(ciWorkflow.contains("SWIFT_TEST_TIMEOUT_SECONDS: \"300\""))
        #expect(ciWorkflow.contains("SWIFT_TEST_WORKERS: \"4\""))
        #expect(ciWorkflow.contains("set -o pipefail\n          mise run test-benchmark 2>&1 | tee benchmark.log"))
    }

    @Test("observability launchers scrub inherited AgentStudio process identity")
    func observabilityLaunchersUseCleanLaunchServicesEnvironment() throws {
        let debugScript = try String(contentsOfFile: "scripts/run-debug-observability.sh", encoding: .utf8)
        let betaScript = try String(contentsOfFile: "scripts/run-beta-observability.sh", encoding: .utf8)

        for script in [debugScript, betaScript] {
            #expect(script.contains("clean_open_env=("))
            #expect(script.contains("open_app()"))
            #expect(script.contains("for attempt in 1 2 3 4 5"))
            #expect(script.contains("-i"))
            #expect(script.contains("\"PATH=/usr/bin:/bin:/usr/sbin:/sbin\""))
            #expect(script.contains("\"${clean_open_env[@]}\" \"$OPEN_BIN\" ${wait_flag:+\"$wait_flag\"} -n"))
            #expect(script.contains("open_app \"$app_path\" \"$launch_log\" \"-W\""))
            #expect(script.contains("\"$OPEN_BIN\" ${wait_flag:+\"$wait_flag\"} -n"))
            #expect(!script.contains("PATH=\"$safe_path\" open -n"))
            #expect(!script.contains("-u MANPATH"))
            #expect(!script.contains("-u XDG_DATA_DIRS"))
            #expect(!script.contains("-u ZMX_DIR"))
            #expect(!script.contains("-u ZMX_SESSION"))
            #expect(!script.contains("-u ZMX_SESSION_PREFIX"))
            #expect(!script.contains("-u __CFBundleIdentifier"))
            #expect(!script.contains("-u GHOSTTY_BIN_DIR"))
            #expect(!script.contains("-u GHOSTTY_RESOURCES_DIR"))
            #expect(script.contains("--stdout \"$launch_log\""))
            #expect(script.contains("--stderr \"$launch_log\""))
            #expect(script.contains("--env \"AGENTSTUDIO_TRACE_BACKEND=$trace_backend\""))
            #expect(script.contains("--env \"AGENTSTUDIO_TRACE_PROOF_TOKEN=$trace_proof_token\""))
            #expect(script.contains("PGREP_BIN=\"${AGENTSTUDIO_PGREP_BIN:-/usr/bin/pgrep}\""))
            #expect(script.contains("LSOF_BIN=\"${AGENTSTUDIO_LSOF_BIN:-/usr/sbin/lsof}\""))
            #expect(script.contains("\"$PGREP_BIN\" -x AgentStudio"))
            #expect(script.contains("unable to inspect running AgentStudio PID $pid"))
            #expect(script.contains("unable to resolve executable for running AgentStudio PID $pid"))
            #expect(script.contains("\"$LSOF_BIN\" -a -p \"$pid\" -d txt -Fn"))
            #expect(!script.contains("ps -axo pid=,command="))
            #expect(script.contains("write_launch_failed_state()"))
            #expect(script.contains("AGENTSTUDIO_OBSERVABILITY_STATUS launch_failed"))
            #expect(script.contains("LaunchServices open failed"))
        }
        #expect(debugScript.contains("AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION"))
        #expect(
            betaScript.contains(
                "BETA_ARTIFACT_ROOT=\"${AGENTSTUDIO_BETA_ARTIFACT_ROOT:-$HOME/.agentstudio-db/beta-observability}\""))
        #expect(betaScript.contains("trace_dir=\"${AGENTSTUDIO_TRACE_DIR:-$BETA_ARTIFACT_ROOT/traces}\""))
        #expect(
            betaScript.contains(
                "launch_log=\"${AGENTSTUDIO_OBSERVABILITY_LAUNCH_LOG:-$BETA_ARTIFACT_ROOT/logs/$trace_name.log}\""))
        #expect(betaScript.contains("--latest-local"))
        #expect(betaScript.contains("missing required --app <AgentStudio Beta.app>"))
        #expect(betaScript.contains("wait_for_beta_app_pid"))
        #expect(betaScript.contains("write_launch_failed_state otlp_collector_unhealthy"))
        #expect(!debugScript.contains("refusing to launch debug observability from inherited zmx environment"))
        #expect(!betaScript.contains("refusing to launch beta observability from inherited zmx environment"))
        #expect(debugScript.contains("AGENTSTUDIO_OBSERVABILITY_LAUNCH_METHOD"))
        #expect(debugScript.contains("wait_for_app_pid"))
        #expect(debugScript.contains("agentstudio_pids_for_binary()"))
        #expect(debugScript.contains("launch_direct_binary()"))
        #expect(debugScript.contains("debug direct executable fallback"))
        #expect(!betaScript.contains("launch_direct_binary()"))
        #expect(!betaScript.contains("direct_executable"))
        #expect(!betaScript.contains("running_app_pids_for_binary()"))
        #expect(!betaScript.contains("agentstudio_pids_for_binary()"))
        #expect(betaScript.contains("running_beta_app_pids()"))
        #expect(betaScript.contains("AgentStudio beta is already running"))
        #expect(betaScript.contains("AGENTSTUDIO_OBSERVABILITY_STATUS already_running"))

        let createBetaScript = try String(contentsOfFile: "scripts/create-local-beta-bundle.sh", encoding: .utf8)
        #expect(
            createBetaScript.contains(
                "beta_artifact_root=\"${AGENTSTUDIO_BETA_ARTIFACT_ROOT:-$HOME/.agentstudio-db/beta-observability}\""))
        #expect(
            createBetaScript.contains(
                "artifact_dir=\"${AGENTSTUDIO_LOCAL_BETA_DIR:-$beta_artifact_root/$marketing_version}\""))
    }

    @Test("beta observability verifier bounds VictoriaLogs queries")
    func betaObservabilityVerifierBoundsVictoriaLogsQueries() throws {
        let verifierScript = try String(contentsOfFile: "scripts/verify-beta-observability.sh", encoding: .utf8)

        #expect(verifierScript.contains("CURL_BIN=\"${AGENTSTUDIO_CURL_BIN:-/usr/bin/curl}\""))
        #expect(verifierScript.contains("\"$CURL_BIN\" --fail --silent --show-error --max-time 5 --get"))
        #expect(
            verifierScript.contains(
                "stream_query=\"{service.name=\\\"AgentStudio\\\",dev.release.channel=\\\"beta\\\"}\""))
        #expect(verifierScript.contains("logsql_escape_exact_value()"))
        #expect(verifierScript.contains("logsql_exact_filter()"))
        #expect(verifierScript.contains("marker_query=\"$(logsql_exact_filter \"agent.proof.marker\" \"$MARKER\")\""))
        #expect(verifierScript.contains("startup_event_query=\"$(logsql_exact_filter \"_msg\""))
        #expect(verifierScript.contains("query=\"$stream_query $marker_query\""))
        #expect(!verifierScript.contains("marker_query=\"agent.proof.marker:${MARKER}\""))
        #expect(!verifierScript.contains("agentstudio.trace.name"))
        #expect(verifierScript.contains("AGENTSTUDIO_EXPECTED_BETA_APP"))
        #expect(verifierScript.contains("missing AGENTSTUDIO_EXPECTED_BETA_APP"))
        #expect(verifierScript.contains("AgentStudio beta observability app mismatch"))
        #expect(verifierScript.contains("shlex.split"))
        #expect(verifierScript.contains("AgentStudio beta observability did not start"))
        #expect(verifierScript.contains("state_status"))
        #expect(verifierScript.contains("state_pid"))
        #expect(verifierScript.contains("bundle_release_channel_for_executable"))
        #expect(verifierScript.contains("app.zmx_startup_reconciliation.completed"))
        #expect(verifierScript.contains("agentstudio.zmx.startup.inventory_outcome"))
        #expect(verifierScript.contains("agentstudio.zmx.startup.protected_session_count"))
        #expect(verifierScript.contains("startup zmx reconciliation inventory was unavailable"))
    }

    @Test("beta observability verifier fails before querying logs when launcher state failed")
    func betaObservabilityVerifierFailsFastForFailedLauncherState() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=launch_failed
        AGENTSTUDIO_OBSERVABILITY_REASON=launchservices_open_failed
        AGENTSTUDIO_OBSERVABILITY_MARKER=marker\\ with\\ spaces
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)
        let curlMarker = fixture.url("curl-called")

        let result = try fixture.runVerifier(
            stateFile: stateFile,
            environment: [
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "curl-fail-health",
                    """
                    #!/bin/bash
                    echo called > "\(curlMarker.path)"
                    exit 0
                    """
                ).path
            ]
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("launch_failed"))
        #expect(result.stderr.contains("launchservices_open_failed"))
        #expect(!FileManager.default.fileExists(atPath: curlMarker.path))
    }

    @Test("beta observability verifier requires exact expected app binding")
    func betaObservabilityVerifierRequiresExactExpectedAppBinding() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=beta-marker
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_APP=\(shellEscapedStateValue(fixture.url("workflow/AgentStudio Beta.app").path))
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)
        let curlMarker = fixture.url("curl-called")

        let result = try fixture.runVerifier(
            stateFile: stateFile,
            environment: [
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "curl",
                    """
                    #!/bin/bash
                    echo called > "\(curlMarker.path)"
                    exit 0
                    """
                ).path
            ]
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("missing AGENTSTUDIO_EXPECTED_BETA_APP"))
        #expect(!FileManager.default.fileExists(atPath: curlMarker.path))
    }

    @Test("beta observability verifier uses configured curl for VictoriaLogs queries")
    func betaObservabilityVerifierUsesConfiguredCurlForQueries() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        let betaApp = try fixture.makeAppBundle(name: "AgentStudioBeta.app", releaseChannel: "beta")
        let betaAppPath = betaApp.path
        let marker = "beta marker | fields process.pid"
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=\(shellEscapedStateValue(marker))
        AGENTSTUDIO_OBSERVABILITY_SERVICE_VERSION=0.0.54-beta.99
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_PID=\(getpid())
        AGENTSTUDIO_OBSERVABILITY_APP=\(shellEscapedStateValue(betaAppPath))
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)
        let curlMarker = fixture.url("curl-called")
        let curlArguments = fixture.url("curl-arguments")

        let result = try fixture.runVerifier(
            stateFile: stateFile,
            environment: [
                "AGENTSTUDIO_EXPECTED_BETA_APP": betaAppPath,
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "curl",
                    """
                    #!/bin/bash
                    echo called >> "\(curlMarker.path)"
                    printf '%s\\n' "$*" >> "\(curlArguments.path)"
                    if [[ "$*" == *"app.zmx_startup_reconciliation.completed"* ]]; then
                      printf '{"_msg":"app.zmx_startup_reconciliation.completed","agentstudio.zmx.startup.inventory_outcome":"complete","agentstudio.zmx.startup.live_session_count":1,"agentstudio.zmx.startup.hydrated_anchor_count":0,"agentstudio.zmx.startup.protected_session_count":1,"agentstudio.zmx.startup.unresolved_candidate_count":0,"agentstudio.zmx.startup.unmatched_live_session_count":0}\\n'
                      exit 0
                    fi
                    if [[ "$*" == *"app.startup_diagnostic_action."* ]]; then
                      exit 0
                    fi
                    if [[ "$*" == *":*"* ]]; then
                      exit 0
                    fi
                    printf '{"service.name":"AgentStudio","service.version":"0.0.54-beta.99","dev.release.channel":"beta","dev.runtime.flavor":"release","_msg":"app.process.start"}\\n'
                    exit 0
                    """
                ).path,
                "AGENTSTUDIO_LSOF_BIN": try fixture.executable(
                    "lsof",
                    """
                    #!/bin/bash
                    echo "n\(betaApp.path)/Contents/MacOS/AgentStudio"
                    echo "n/Library/Preferences/Logging/.plist-cache.test"
                    echo "n/usr/lib/dyld"
                    """
                ).path,
            ]
        )

        #expect(result.exitCode == 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        #expect(FileManager.default.fileExists(atPath: curlMarker.path))
        let curlArgumentText = try String(contentsOf: curlArguments, encoding: .utf8)
        let expectedTraceQuery = [
            "{service.name=\"AgentStudio\",dev.release.channel=\"beta\"}",
            "agent.proof.marker:=\"beta marker | fields process.pid\"",
        ].joined(separator: " ")
        #expect(curlArgumentText.contains(expectedTraceQuery))
        #expect(!curlArgumentText.contains("agent.proof.marker:beta marker | fields process.pid"))
        #expect(!curlArgumentText.contains("agentstudio.trace.name"))
    }

    @Test("beta observability verifier rejects PID from a different beta bundle path")
    func betaObservabilityVerifierRejectsPidFromDifferentBetaBundlePath() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        let expectedApp = try fixture.makeAppBundle(name: "Expected AgentStudio Beta.app", releaseChannel: "beta")
        let actualRunningApp = try fixture.makeAppBundle(name: "Other AgentStudio Beta.app", releaseChannel: "beta")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=beta-marker
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_PID=\(getpid())
        AGENTSTUDIO_OBSERVABILITY_APP=\(shellEscapedStateValue(expectedApp.path))
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)
        let curlMarker = fixture.url("curl-called")

        let result = try fixture.runVerifier(
            stateFile: stateFile,
            environment: [
                "AGENTSTUDIO_EXPECTED_BETA_APP": expectedApp.path,
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "curl",
                    """
                    #!/bin/bash
                    echo called > "\(curlMarker.path)"
                    exit 0
                    """
                ).path,
                "AGENTSTUDIO_LSOF_BIN": try fixture.executable(
                    "lsof",
                    """
                    #!/bin/bash
                    echo "n\(actualRunningApp.path)/Contents/MacOS/AgentStudio"
                    """
                ).path,
            ]
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("PID app mismatch"))
        #expect(!FileManager.default.fileExists(atPath: curlMarker.path))
    }

    @Test("beta observability verifier rejects stale running state before querying logs")
    func betaObservabilityVerifierRejectsStaleRunningStateBeforeQueryingLogs() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        let betaAppPath = try fixture.makeAppBundle(name: "AgentStudioBeta.app", releaseChannel: "beta").path
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=beta-marker
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_PID=999999999
        AGENTSTUDIO_OBSERVABILITY_APP=\(shellEscapedStateValue(betaAppPath))
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)
        let curlMarker = fixture.url("curl-called")

        let result = try fixture.runVerifier(
            stateFile: stateFile,
            environment: [
                "AGENTSTUDIO_EXPECTED_BETA_APP": betaAppPath,
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "curl",
                    """
                    #!/bin/bash
                    echo called > "\(curlMarker.path)"
                    printf '{"service.name":"AgentStudio","service.version":"0.0.54-beta.99","dev.release.channel":"beta","_msg":"app.process.start"}\\n'
                    exit 0
                    """
                ).path,
            ]
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("PID is not running"))
        #expect(!FileManager.default.fileExists(atPath: curlMarker.path))
    }

    @Test("beta observability verifier fails when startup reconciliation telemetry is missing")
    func betaObservabilityVerifierFailsWhenStartupReconciliationTelemetryIsMissing() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        let betaApp = try fixture.makeAppBundle(name: "AgentStudioBeta.app", releaseChannel: "beta")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=beta-marker
        AGENTSTUDIO_OBSERVABILITY_SERVICE_VERSION=0.0.54-beta.99
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_PID=\(getpid())
        AGENTSTUDIO_OBSERVABILITY_APP=\(shellEscapedStateValue(betaApp.path))
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)

        let result = try fixture.runVerifier(
            stateFile: stateFile,
            environment: [
                "AGENTSTUDIO_EXPECTED_BETA_APP": betaApp.path,
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "curl",
                    """
                    #!/bin/bash
                    if [[ "$*" == *"app.zmx_startup_reconciliation.completed"* ]] || [[ "$*" == *":* | limit 1"* ]]; then
                      exit 0
                    fi
                    printf '{"service.name":"AgentStudio","service.version":"0.0.54-beta.99","dev.release.channel":"beta","dev.runtime.flavor":"release","_msg":"app.process.start"}\\n'
                    exit 0
                    """
                ).path,
                "AGENTSTUDIO_LSOF_BIN": try fixture.executable(
                    "lsof",
                    """
                    #!/bin/bash
                    echo "n\(betaApp.path)/Contents/MacOS/AgentStudio"
                    """
                ).path,
            ]
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("no startup zmx reconciliation record"))
    }

    @Test("beta observability verifier rejects unexpected beta app path")
    func betaObservabilityVerifierRejectsUnexpectedBetaAppPath() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=beta-marker
        AGENTSTUDIO_OBSERVABILITY_SERVICE_VERSION=0.0.54-beta.99
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_APP=\(fixture.url("stale/AgentStudio Beta.app").path)
        """.write(to: stateFile, atomically: true, encoding: .utf8)
        let curlMarker = fixture.url("curl-called")

        let result = try fixture.runVerifier(
            stateFile: stateFile,
            environment: [
                "AGENTSTUDIO_EXPECTED_BETA_APP": fixture.url("workflow/AgentStudio Beta.app").path,
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
        #expect(result.stderr.contains("AgentStudio beta observability app mismatch"))
        #expect(!FileManager.default.fileExists(atPath: curlMarker.path))
    }

    @Test("debug observability verifier requires startup reconciliation telemetry and scrubbed output")
    func debugObservabilityVerifierRequiresStartupReconciliationTelemetryAndScrubbedOutput() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        let marker = "debug marker | fields process.pid"
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=\(shellEscapedStateValue(marker))
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=testcode
        AGENTSTUDIO_OBSERVABILITY_PID=\(getpid())
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_APP=\(shellEscapedStateValue(fixture.url("Agent Studio Debug testcode.app").path))
        """.write(to: stateFile, atomically: true, encoding: .utf8)
        let debugApp = try fixture.makeAppBundle(
            name: "Agent Studio Debug testcode.app",
            releaseChannel: "stable",
            bundleIdentifier: "com.agentstudio.app.debug.dtestcode"
        )
        let curlMarker = fixture.url("curl-called")
        let curlArguments = fixture.url("curl-arguments")

        let result = try fixture.runVerifier(
            scriptPath: "scripts/verify-debug-observability.sh",
            stateFile: stateFile,
            environment: [
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "curl",
                    """
                    #!/bin/bash
                    echo called >> "\(curlMarker.path)"
                    printf '%s\\n' "$*" >> "\(curlArguments.path)"
                    if [[ "$*" == *"app.zmx_startup_reconciliation.completed"* ]]; then
                      printf '{"_msg":"app.zmx_startup_reconciliation.completed","agentstudio.zmx.startup.inventory_outcome":"complete","agentstudio.zmx.startup.live_session_count":1,"agentstudio.zmx.startup.hydrated_anchor_count":0,"agentstudio.zmx.startup.protected_session_count":1,"agentstudio.zmx.startup.unresolved_candidate_count":0,"agentstudio.zmx.startup.unmatched_live_session_count":0}\\n'
                      exit 0
                    fi
                    if [[ "$*" == *"app.startup_diagnostic_action."* ]]; then
                      exit 0
                    fi
                    if [[ "$*" == *":*"* ]]; then
                      exit 0
                    fi
                    printf '{"service.name":"AgentStudio","service.version":"0.0.1-debug+abcd1234","dev.runtime.flavor":"debug","_msg":"app.process.start"}\\n'
                    exit 0
                    """
                ).path,
                "AGENTSTUDIO_LSOF_BIN": try fixture.executable(
                    "lsof",
                    """
                    #!/bin/bash
                    echo "n\(debugApp.path)/Contents/MacOS/AgentStudio"
                    echo "n/Library/Preferences/Logging/.plist-cache.test"
                    echo "n/usr/lib/dyld"
                    """
                ).path,
            ]
        )

        #expect(result.exitCode == 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        #expect(FileManager.default.fileExists(atPath: curlMarker.path))
        let curlArgumentText = try String(contentsOf: curlArguments, encoding: .utf8)
        let expectedTraceQuery = [
            "{service.name=\"AgentStudio\",dev.runtime.flavor=\"debug\"}",
            "agent.proof.marker:=\"debug marker | fields process.pid\"",
        ].joined(separator: " ")
        #expect(curlArgumentText.contains(expectedTraceQuery))
        #expect(!curlArgumentText.contains("agent.proof.marker:debug marker | fields process.pid"))
        #expect(!curlArgumentText.contains("agentstudio.trace.name"))
    }

    @Test("debug observability verifier fails when startup reconciliation telemetry is missing")
    func debugObservabilityVerifierFailsWhenStartupReconciliationTelemetryIsMissing() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=debug-marker
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=testcode
        AGENTSTUDIO_OBSERVABILITY_PID=\(getpid())
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_APP=\(shellEscapedStateValue(fixture.url("Agent Studio Debug testcode.app").path))
        """.write(to: stateFile, atomically: true, encoding: .utf8)
        let debugApp = try fixture.makeAppBundle(
            name: "Agent Studio Debug testcode.app",
            releaseChannel: "stable",
            bundleIdentifier: "com.agentstudio.app.debug.dtestcode"
        )

        let result = try fixture.runVerifier(
            scriptPath: "scripts/verify-debug-observability.sh",
            stateFile: stateFile,
            environment: [
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "curl",
                    """
                    #!/bin/bash
                    if [[ "$*" == *":* | limit 1"* ]] || [[ "$*" == *"app.zmx_startup_reconciliation.completed"* ]]; then
                      exit 0
                    fi
                    printf '{"service.name":"AgentStudio","service.version":"0.0.1-debug+abcd1234","dev.runtime.flavor":"debug","_msg":"app.process.start"}\\n'
                    exit 0
                    """
                ).path,
                "AGENTSTUDIO_LSOF_BIN": try fixture.executable(
                    "lsof",
                    """
                    #!/bin/bash
                    echo "n\(debugApp.path)/Contents/MacOS/AgentStudio"
                    """
                ).path,
            ]
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("no startup zmx reconciliation record"))
    }

    @Test("debug observability verifier rejects unavailable startup inventory by default")
    func debugObservabilityVerifierRejectsUnavailableStartupInventoryByDefault() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=debug-marker
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=testcode
        AGENTSTUDIO_OBSERVABILITY_PID=\(getpid())
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_APP=\(shellEscapedStateValue(fixture.url("Agent Studio Debug testcode.app").path))
        """.write(to: stateFile, atomically: true, encoding: .utf8)
        let debugApp = try fixture.makeAppBundle(
            name: "Agent Studio Debug testcode.app",
            releaseChannel: "stable",
            bundleIdentifier: "com.agentstudio.app.debug.dtestcode"
        )

        let result = try fixture.runVerifier(
            scriptPath: "scripts/verify-debug-observability.sh",
            stateFile: stateFile,
            environment: [
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "curl",
                    """
                    #!/bin/bash
                    if [[ "$*" == *"app.zmx_startup_reconciliation.completed"* ]]; then
                      printf '{"_msg":"app.zmx_startup_reconciliation.completed","agentstudio.zmx.startup.inventory_outcome":"unavailable","agentstudio.zmx.startup.live_session_count":0,"agentstudio.zmx.startup.hydrated_anchor_count":0,"agentstudio.zmx.startup.protected_session_count":0,"agentstudio.zmx.startup.unresolved_candidate_count":1,"agentstudio.zmx.startup.unmatched_live_session_count":0}\\n'
                      exit 0
                    fi
                    if [[ "$*" == *":* | limit 1"* ]]; then
                      exit 0
                    fi
                    printf '{"service.name":"AgentStudio","service.version":"0.0.1-debug+abcd1234","dev.runtime.flavor":"debug","_msg":"app.process.start"}\\n'
                    exit 0
                    """
                ).path,
                "AGENTSTUDIO_LSOF_BIN": try fixture.executable(
                    "lsof",
                    """
                    #!/bin/bash
                    echo "n\(debugApp.path)/Contents/MacOS/AgentStudio"
                    """
                ).path,
            ]
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("inventory was unavailable"))
    }

    @Test("debug observability verifier rejects stale running state before querying logs")
    func debugObservabilityVerifierRejectsStaleRunningStateBeforeQueryingLogs() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=debug-marker
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=testcode
        AGENTSTUDIO_OBSERVABILITY_PID=999999999
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-12T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_APP=\(shellEscapedStateValue(fixture.url("Agent Studio Debug testcode.app").path))
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)
        let curlMarker = fixture.url("curl-called")

        let result = try fixture.runVerifier(
            scriptPath: "scripts/verify-debug-observability.sh",
            stateFile: stateFile,
            environment: [
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "curl",
                    """
                    #!/bin/bash
                    echo called > "\(curlMarker.path)"
                    printf '{"service.name":"AgentStudio","service.version":"0.0.1-debug+testcode","dev.runtime.flavor":"debug","_msg":"app.process.start"}\\n'
                    exit 0
                    """
                ).path
            ]
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("PID is not running"))
        #expect(!FileManager.default.fileExists(atPath: curlMarker.path))
    }

}

@Suite("Observability beta launcher scripts")
struct ObservabilityBetaLauncherScriptsTests {
    @Test("beta launcher uses latest local artifact only when explicitly requested")
    func betaLauncherUsesLatestLocalArtifactOnlyWhenExplicitlyRequested() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let primaryRoot = fixture.url("primary-beta-root")
        let legacyRoot = fixture.url("legacy-beta-root")
        let primaryApp = try fixture.makeAppBundle(
            name: "primary-beta-root/0.0.54-beta.16/AgentStudio Beta.app",
            releaseChannel: "beta"
        )
        let legacyApp = try fixture.makeAppBundle(
            name: "legacy-beta-root/0.0.54-beta.99/AgentStudio Beta.app",
            releaseChannel: "beta"
        )
        let staleTouchDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerTouchDate = Date(timeIntervalSince1970: 1_800_000_000)
        try FileManager.default.setAttributes([.modificationDate: staleTouchDate], ofItemAtPath: primaryApp.path)
        try FileManager.default.setAttributes([.modificationDate: newerTouchDate], ofItemAtPath: legacyApp.path)
        let openArgs = fixture.url("open-args")
        let stateFile = fixture.url("latest.env")

        let result = try fixture.runScript(
            "scripts/run-beta-observability.sh",
            arguments: ["--latest-local", "--detach"],
            environment: [
                "AGENTSTUDIO_BETA_ARTIFACT_ROOT": primaryRoot.path,
                "AGENTSTUDIO_LEGACY_BETA_ARTIFACT_ROOT": legacyRoot.path,
                "AGENTSTUDIO_OPEN_BIN": try fixture.executable(
                    "open",
                    """
                    #!/bin/bash
                    printf '%s\\n' "$@" > "\(openArgs.path)"
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
                "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path,
            ]
        )

        #expect(result.exitCode == 1)
        let args = try String(contentsOf: openArgs, encoding: .utf8)
        #expect(args.contains(primaryApp.path))
        #expect(!args.contains(legacyApp.path))
    }

    @Test("beta launcher requires explicit app unless latest local diagnostic mode is selected")
    func betaLauncherRequiresExplicitAppUnlessLatestLocalDiagnosticModeIsSelected() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let openMarker = fixture.url("open-called")

        let result = try fixture.runScript(
            "scripts/run-beta-observability.sh",
            arguments: ["--detach"],
            environment: [
                "AGENTSTUDIO_OPEN_BIN": try fixture.executable(
                    "open",
                    """
                    #!/bin/bash
                    echo called > "\(openMarker.path)"
                    exit 0
                    """
                ).path
            ]
        )

        #expect(result.exitCode == 2)
        #expect(result.stderr.contains("missing required --app"))
        #expect(!FileManager.default.fileExists(atPath: openMarker.path))
    }

    @Test("beta launcher records launch failure when no PID appears")
    func betaLauncherRecordsPidLookupFailureState() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let app = try fixture.makeAppBundle(name: "AgentStudio Beta.app", releaseChannel: "beta")
        let openMarker = fixture.url("open-called")
        let stateFile = fixture.url("latest.env")

        let result = try fixture.runScript(
            "scripts/run-beta-observability.sh",
            arguments: ["--app", app.path, "--detach"],
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
                "AGENTSTUDIO_PID_WAIT_ATTEMPTS": "1",
                "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path,
            ]
        )

        #expect(result.exitCode == 1)
        #expect(FileManager.default.fileExists(atPath: openMarker.path))
        let state = try String(contentsOf: stateFile, encoding: .utf8)
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_STATUS=launch_failed"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_REASON=launchservices_pid_not_found"))
    }

    @Test("beta launcher records launch failure when collector is unhealthy")
    func betaLauncherRecordsCollectorHealthFailureState() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let app = try fixture.makeAppBundle(name: "AgentStudio Beta.app", releaseChannel: "beta")
        let openMarker = fixture.url("open-called")
        let stateFile = fixture.url("latest.env")

        let result = try fixture.runScript(
            "scripts/run-beta-observability.sh",
            arguments: ["--app", app.path, "--detach"],
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
        #expect(!FileManager.default.fileExists(atPath: openMarker.path))
        let state = try String(contentsOf: stateFile, encoding: .utf8)
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_STATUS=launch_failed"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_REASON=otlp_collector_unhealthy"))
    }

    @Test("beta launcher does not bind launched proof to a different beta bundle path")
    func betaLauncherDoesNotBindProofToDifferentBetaBundlePathAfterLaunch() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let selectedApp = try fixture.makeAppBundle(name: "Selected AgentStudio Beta.app", releaseChannel: "beta")
        let translocatedApp = try fixture.makeAppBundle(
            name: "Translocated/AgentStudio Beta.app", releaseChannel: "beta")
        let pgrepState = fixture.url("pgrep-state")
        let stateFile = fixture.url("latest.env")

        let result = try fixture.runScript(
            "scripts/run-beta-observability.sh",
            arguments: ["--app", selectedApp.path, "--detach"],
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
                    if [ -f "\(pgrepState.path)" ]; then
                      echo 6464
                    else
                      touch "\(pgrepState.path)"
                      exit 1
                    fi
                    """
                ).path,
                "AGENTSTUDIO_LSOF_BIN": try fixture.executable(
                    "lsof",
                    """
                    #!/bin/bash
                    echo "n\(translocatedApp.path)/Contents/MacOS/AgentStudio"
                    """
                ).path,
                "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path,
                "AGENTSTUDIO_PID_WAIT_ATTEMPTS": "1",
            ]
        )

        #expect(result.exitCode == 1)
        let state = try String(contentsOf: stateFile, encoding: .utf8)
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_STATUS=launch_failed"))
        #expect(state.contains("AGENTSTUDIO_OBSERVABILITY_REASON=launchservices_pid_not_found"))
    }

}
