import AgentStudioInfrastructure
import Foundation
import Testing

@Suite("Swift lane fast shard hang evidence")
struct SwiftLaneFastShardHangEvidenceTests {
    @Test("a missing fact inside a shard is named and the shard process group is reaped")
    func missingFactInsideShardIsReportedAndItsProcessGroupIsReaped() async throws {
        let fixture = try FastShardHangFixture()
        defer { fixture.remove() }
        let result = try await fixture.runLane()
        let recordedReapStages = ["sigint_cancelled", "terminated", "killed"]

        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(result.output.contains("native fast shards=1 capacity=250 concurrency=3"))
        #expect(result.output.contains("no output progress from 'native fast shard 001' for 0s"))
        #expect(result.output.contains(fixture.expectedFact), Comment(rawValue: result.output))
        #expect(
            recordedReapStages.contains { result.output.contains("lane-report timeout_reap=\($0)") },
            Comment(rawValue: result.output)
        )
        #expect(result.output.contains("lane-report fast_shard_command_status=1"))
        #expect(result.output.contains("lane-report fast_shard_coverage_status=1"))
        #expect(result.output.contains("SHARD_RUN_STATUS=1"))
        #expect(result.output.contains("SHARD_HELPER_ALIVE=no"))
        #expect(result.output.contains("SHARD_PROCESS_GROUP_ALIVE=no"))
    }

    private struct FastShardHangFixture {
        let root: URL
        let scriptDirectory: URL
        let buildPath: URL
        let helperPath: URL
        let bundlePath: URL
        let helperPIDFile: URL
        let releaseFIFO: URL
        let testID: String
        let expectedFact: String

        init() throws {
            let fixtureRoot = FileManager.default.temporaryDirectory
                .appending(path: "swift-fast-shard-hang-\(UUIDv7.generate().uuidString)")
            let fixtureScripts = fixtureRoot.appending(path: "scripts")
            let fixtureBuildPath = fixtureRoot.appending(path: "build")
            let fixtureHelper = fixtureScripts.appending(path: "fake-swiftpm-testing-helper.sh")
            let fixtureBundle = fixtureBuildPath.appending(
                path: "debug/AgentStudioPackageTests.xctest/Contents/MacOS/AgentStudioPackageTests")
            let fixturePIDFile = fixtureRoot.appending(path: "shard-helper-pid")
            let fixtureReleaseFIFO = fixtureRoot.appending(path: "shard-helper-release")
            let suiteID = "AgentStudioTests.ShardHangFixtureTests"
            let functionID = "\(suiteID)/waitsForNamedFact()"
            let fixtureTestID = "\(functionID)/ShardHangFixtureTests.swift:42:5"

            root = fixtureRoot
            scriptDirectory = fixtureScripts
            buildPath = fixtureBuildPath
            helperPath = fixtureHelper
            bundlePath = fixtureBundle
            helperPIDFile = fixturePIDFile
            releaseFIFO = fixtureReleaseFIFO
            testID = fixtureTestID
            expectedFact =
                "lane-report fact_expected id=shard-refresh-fact expected=workspaceRefreshCommitted "
                + "scope=project-worktree-42 test=\(fixtureTestID) "
                + "site=ShardHangFixtureTests.swift:42 waitsForNamedFact()"

            try FileManager.default.createDirectory(at: fixtureScripts, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: fixtureBundle.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: fixtureRoot.appending(path: "frameworks"), withIntermediateDirectories: true
            )
            try Self.copyRunnerScripts(to: fixtureScripts)
            try Self.writeManifest(
                at: fixtureScripts.appending(path: "swift-test-fast-shard-manifest.json"),
                suiteID: suiteID,
                functionID: functionID
            )
            _ = FileManager.default.createFile(atPath: fixtureBundle.path, contents: Data())
            try Self.writeFakeHelper(at: fixtureHelper, suiteID: suiteID, testID: fixtureTestID)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }

        func runLane() async throws -> LaneScriptBashResult {
            try await runLaneScriptBash(shellCommand())
        }

        private func shellCommand() -> String {
            let helperScript = Self.shellQuote(scriptDirectory.appending(path: "swift-test-helpers.sh").path)
            return """
                set +e
                LOG_PREFIX=shard-test
                TIMEOUT_SECONDS=0
                PREBUILD_TIMEOUT_SECONDS=60
                BUILD_PATH=\(Self.shellQuote(buildPath.path))
                LANE_EVENT_STREAM_DIR=\(Self.shellQuote(root.appending(path: "lane-events").path))
                LANE_WATCHDOG_ARM_PATH=\(Self.shellQuote(root.appending(path: "watchdog-armed").path))
                SWIFT_TEST_RESOURCE_TIMER=\(Self.shellQuote(root.appending(path: "missing-resource-timer").path))
                SHARD_TEST_BUNDLE=\(Self.shellQuote(bundlePath.path))
                SHARD_FAKE_HELPER=\(Self.shellQuote(helperPath.path))
                SHARD_FRAMEWORKS=\(Self.shellQuote(root.appending(path: "frameworks").path))
                SHARD_HANG_PID_FILE=\(Self.shellQuote(helperPIDFile.path))
                SHARD_HANG_RELEASE_FIFO=\(Self.shellQuote(releaseFIFO.path))
                export LOG_PREFIX TIMEOUT_SECONDS PREBUILD_TIMEOUT_SECONDS BUILD_PATH LANE_EVENT_STREAM_DIR
                export LANE_WATCHDOG_ARM_PATH SWIFT_TEST_RESOURCE_TIMER SHARD_TEST_BUNDLE SHARD_FAKE_HELPER
                export SHARD_FRAMEWORKS SHARD_HANG_PID_FILE SHARD_HANG_RELEASE_FIFO
                source \(helperScript)
                swift_test_suite_lane_inventory() {
                  printf '%s\\n' 'fast|ShardHangFixtureTests|concurrent'
                }
                swift_testing_bundle_path() { printf '%s\\n' "$SHARD_TEST_BUNDLE"; }
                swift_testing_helper_path() { printf '%s\\n' "$SHARD_FAKE_HELPER"; }
                swift_testing_framework_path() { printf '%s\\n' "$SHARD_FRAMEWORKS"; }
                _xcb_pipe_cmd() { printf '%s\\n' cat; }
                mkfifo "$SHARD_HANG_RELEASE_FIFO"
                shard_status=0
                run_fast_sharded_native_swift_tests || shard_status=$?
                read -r helper_pid helper_pgid < "$SHARD_HANG_PID_FILE"
                if swift_test_process_id_has_survivors "$helper_pid"; then helper_alive=yes; else helper_alive=no; fi
                if swift_test_process_group_has_survivors "$helper_pgid"; then group_alive=yes; else group_alive=no; fi
                printf 'SHARD_RUN_STATUS=%s\\nSHARD_HELPER_PID=%s\\nSHARD_HELPER_PGID=%s\\n' \\
                  "$shard_status" "$helper_pid" "$helper_pgid"
                printf 'SHARD_HELPER_ALIVE=%s\\nSHARD_PROCESS_GROUP_ALIVE=%s\\n' "$helper_alive" "$group_alive"
                """
        }

        private static func copyRunnerScripts(to scriptDirectory: URL) throws {
            for scriptName in [
                "swift-test-helpers.sh",
                "swift-test-fast-shard-inventory.pl",
                "swift-test-output-relay.pl",
                "swift-test-invocation-receipts.sh",
                "swift-test-invocation-receipts.pl",
                "swift-package-sandbox.sh",
                "xcb-helpers.sh",
                "filter-known-linker-warnings.sh",
            ] {
                try FileManager.default.copyItem(
                    atPath: "scripts/\(scriptName)",
                    toPath: scriptDirectory.appending(path: scriptName).path
                )
            }
        }

        private static func writeManifest(at path: URL, suiteID: String, functionID: String) throws {
            let manifest = """
                {"schema_version":1,"source_run_id":"shard-hang-fixture","source_head_sha":"fixture","suites":[{"id":"\(suiteID)","type_path":"ShardHangFixtureTests"}],"functions":[{"id":"\(functionID)","suite_id":"\(suiteID)","name":"waitsForNamedFact()","parameterized":false,"case_count":0,"case_display_names":[],"stable_case_ids":[],"unstable_case_count":0}]}
                """
            try Data(manifest.utf8).write(to: path)
        }

        private static func writeFakeHelper(at path: URL, suiteID: String, testID: String) throws {
            let eventStream = """
                {"kind":"test","payload":{"id":"\(suiteID)","kind":"suite","name":"ShardHangFixtureTests"},"version":0}
                {"kind":"test","payload":{"id":"\(testID)","isParameterized":false,"kind":"function","name":"waitsForNamedFact()"},"version":0}
                {"kind":"event","payload":{"kind":"runStarted"},"version":0}
                {"kind":"event","payload":{"kind":"testStarted","testID":"\(testID)"},"version":0}
                """
            let script = """
                #!/bin/bash
                set -eu
                trap 'exit 0' INT TERM
                event_stream_file=""
                while [ "$#" -gt 0 ]; do
                  if [ "$1" = "--event-stream-output-path" ]; then
                    event_stream_file="$2"
                    shift 2
                  else
                    shift
                  fi
                done
                [ -n "$event_stream_file" ]
                cat > "$event_stream_file" <<'SHARD_EVENTS'
                \(eventStream)
                SHARD_EVENTS
                printf 'expecting\\tshard-refresh-fact\\tworkspaceRefreshCommitted\\tproject-worktree-42\\t\(testID)\\tShardHangFixtureTests.swift:42 waitsForNamedFact()\\n' \\
                  >> "$AGENTSTUDIO_HELD_STEP_LOG"
                printf '%s %s\\n' "$$" "$(/usr/bin/perl -MPOSIX -e 'print POSIX::getpgrp()')" > "$SHARD_HANG_PID_FILE"
                printf '[shard-fixture] reached waitsForNamedFact\\n'
                touch "$LANE_WATCHDOG_ARM_PATH"
                read -r release < "$SHARD_HANG_RELEASE_FIFO"
                """
            try script.write(to: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        }

        private static func shellQuote(_ value: String) -> String {
            "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
        }
    }
}
