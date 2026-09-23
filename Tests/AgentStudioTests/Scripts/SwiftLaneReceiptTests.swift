import AgentStudioInfrastructure
import Foundation
import Testing

@Suite("Swift lane receipts and hang evidence")
struct SwiftLaneReceiptTests {
    @Test("a receipt is valid only for a bundle this invocation built from a clean tree")
    func receiptIsValidOnlyForFreshBundleAndCleanTree() async throws {
        let reasons = try await laneBash(
            "source scripts/swift-test-helpers.sh; "
                + "for pair in 'fresh false' 'reused false' 'not_built false' 'fresh true' "
                + "'reused true' 'fresh unknown'; do "
                + "set -- $pair; echo \"$1/$2=[$(lane_receipt_invalid_reasons \"$1\" \"$2\")]\"; done"
        )

        #expect(
            reasons.split(separator: "\n").map(String.init) == [
                "fresh/false=[]",
                "reused/false=[reused_bundle]",
                "not_built/false=[unbuilt_bundle]",
                "fresh/true=[dirty_tree]",
                "reused/true=[reused_bundle,dirty_tree]",
                "fresh/unknown=[unknown_tree]",
            ]
        )
    }

    @Test("only a valid receipt carries a verdict, and an invalid one is never a pass")
    func onlyValidReceiptCarriesVerdict() async throws {
        let validPass = try await laneBash(
            "LOG_PREFIX=lane; source scripts/swift-test-helpers.sh; print_lane_receipt_verdict 0 fresh false"
        )
        let validFail = try await laneBash(
            "LOG_PREFIX=lane; source scripts/swift-test-helpers.sh; print_lane_receipt_verdict 1 fresh false"
        )
        let reusedPass = try await laneBash(
            "LOG_PREFIX=lane; source scripts/swift-test-helpers.sh; print_lane_receipt_verdict 0 reused false"
        )
        let dirtyPass = try await laneBash(
            "LOG_PREFIX=lane; source scripts/swift-test-helpers.sh; print_lane_receipt_verdict 0 fresh true"
        )

        #expect(lines(validPass) == ["[lane] lane-report receipt_valid=true", "[lane] lane-report verdict=pass"])
        #expect(lines(validFail) == ["[lane] lane-report receipt_valid=true", "[lane] lane-report verdict=fail"])
        // A reused bundle or a dirty tree passing is not evidence about the commit.
        #expect(
            lines(reusedPass) == [
                "[lane] lane-report receipt_valid=false reason=reused_bundle",
                "[lane] lane-report verdict=unverified",
            ]
        )
        #expect(
            lines(dirtyPass) == [
                "[lane] lane-report receipt_valid=false reason=dirty_tree",
                "[lane] lane-report verdict=unverified",
            ]
        )
    }

    @Test("the closing tree state catches edits and commits made while the lane ran")
    func closingTreeStateCatchesChangesDuringTheLane() async throws {
        let repositoryDirectory = NSTemporaryDirectory() + "agentstudio-receipt-tree-\(UUIDv7.generate())"
        defer { try? FileManager.default.removeItem(atPath: repositoryDirectory) }
        let helperPath = FileManager.default.currentDirectoryPath + "/scripts/swift-test-helpers.sh"

        let states = try await laneBash(
            "source '\(helperPath)'; mkdir -p '\(repositoryDirectory)'; cd '\(repositoryDirectory)'; "
                + "git init -q . 2>/dev/null; "
                + "commit() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "
                + "-c core.hooksPath=/dev/null commit -q --allow-empty -m \"$1\"; }; commit one; "
                + "opening=$(lane_receipt_head_sha); "
                + "echo \"clean=$(lane_receipt_tree_dirty)\"; "
                + "echo \"clean_since=$(lane_receipt_tree_dirty_since \"$opening\" false)\"; "
                + "echo edit > untracked.txt; "
                + "echo \"edited_since=$(lane_receipt_tree_dirty_since \"$opening\" false)\"; "
                + "rm untracked.txt; "
                + "commit two; "
                + "echo \"moved_since=$(lane_receipt_tree_dirty_since \"$opening\" false)\"; "
                + "echo \"opened_dirty=$(lane_receipt_tree_dirty_since \"$opening\" true)\"; "
                + "cd /; echo \"outside=$(lane_receipt_tree_dirty) head=$(lane_receipt_head_sha)\""
        )

        #expect(
            lines(states) == [
                "clean=false",
                "clean_since=false",
                "edited_since=true",
                "moved_since=true",
                "opened_dirty=true",
                "outside=unknown head=unknown",
            ]
        )
    }

    @Test("bundle identity names the built bundle and its modification time")
    func bundleIdentityNamesBundleAndModificationTime() async throws {
        let buildDirectory = NSTemporaryDirectory() + "agentstudio-receipt-bundle-\(UUIDv7.generate())"
        defer { try? FileManager.default.removeItem(atPath: buildDirectory) }
        let bundlePath =
            buildDirectory
            + "/arm64-apple-macosx/debug/AgentStudioPackageTests.xctest/Contents/MacOS/AgentStudioPackageTests"

        let identities = try await laneBash(
            "source scripts/swift-test-helpers.sh; BUILD_PATH='\(buildDirectory)'; "
                + "echo \"before=$(lane_receipt_bundle_identity)\"; "
                + "mkdir -p \"$(dirname '\(bundlePath)')\"; : > '\(bundlePath)'; "
                + "touch -t 202609230102.03 '\(bundlePath)'; "
                + "echo \"after=$(lane_receipt_bundle_identity)\"; "
                + "echo \"epoch=$(date -j -f %Y%m%d%H%M.%S 202609230102.03 +%s)\""
        )
        let identityLines = lines(identities)
        let epoch = try #require(identityLines.last?.split(separator: "=").last.map(String.init))

        #expect(identityLines.first == "before=missing")
        #expect(identityLines.dropFirst().first == "after=\(bundlePath)@\(epoch)")
    }

    @Test("the receipt is printed on every exit, prebuild included, and only a finished prebuild is fresh")
    func receiptIsPrintedOnEveryExitAndOnlyFinishedPrebuildIsFresh() throws {
        let laneRunnerScript = try String(contentsOfFile: "scripts/run-swift-test-task.sh", encoding: .utf8)
        let trapRange = try #require(laneRunnerScript.range(of: "trap finish_lane_invocation EXIT"))
        let prebuildCallRange = try #require(
            laneRunnerScript.range(of: "  prebuild_swift_tests\n  LANE_BUNDLE_STATE=fresh\n")
        )
        let prebuildExitRange = try #require(
            laneRunnerScript.range(of: "if [ \"$mode\" = \"test-prebuild\" ]; then\n  exit 0\nfi")
        )
        let freshAssignments = laneRunnerScript.components(separatedBy: "LANE_BUNDLE_STATE=fresh").count - 1

        // The trap is armed before anything can build or exit, so test-prebuild
        // and a failing prebuild both still print a closing receipt.
        #expect(trapRange.upperBound < prebuildCallRange.lowerBound)
        #expect(prebuildCallRange.upperBound < prebuildExitRange.lowerBound)
        #expect(laneRunnerScript.contains("LANE_BUNDLE_STATE=not_built\ntrap finish_lane_invocation EXIT"))
        // `fresh` is written in exactly one place: right after this invocation's
        // own prebuild returned successfully under `set -e`.
        #expect(freshAssignments == 1)
        #expect(laneRunnerScript.contains("  LANE_BUNDLE_STATE=reused\n"))
        // test-prebuild always builds: only the other modes may skip the prebuild.
        #expect(
            laneRunnerScript.contains(
                "if [ \"$mode\" != \"test-prebuild\" ] && [ \"${SWIFT_TEST_SKIP_PREBUILD:-0}\" = \"1\" ]; then"
            )
        )
        #expect(
            laneRunnerScript.contains("test|test-fast|test-large|test-prebuild|test-webkit|test-width-comparison)")
        )
    }

    @Test("the build-slot release survives the receipt taking over EXIT")
    func buildSlotReleaseSurvivesReceiptTakingOverExit() async throws {
        let laneRunnerScript = try String(contentsOfFile: "scripts/run-swift-test-task.sh", encoding: .utf8)
        let invocationExit = try laneScriptShellFunction(named: "finish_lane_invocation", in: laneRunnerScript)
        let claimDirectory = NSTemporaryDirectory() + "agentstudio-receipt-claim-\(UUIDv7.generate())"
        defer { try? FileManager.default.removeItem(atPath: claimDirectory) }

        // The runner's own takeover line, run under a trap shaped like
        // swift-build-slot.sh's, after which a second EXIT trap replaces it. The
        // control script replaces the trap without the takeover: that is the leak.
        let takeoverLine = try #require(
            laneRunnerScript.split(separator: "\n").first { $0.hasPrefix("LANE_SLOT_RELEASE_COMMAND=") }
        )
        func slotScript(takingOver: Bool, claim: String) -> String {
            [
                "set -euo pipefail",
                "trap \"rm -rf '\(claim)'\" EXIT",
                takingOver ? String(takeoverLine) : "LANE_SLOT_RELEASE_COMMAND=''",
                "trap 'eval \"$LANE_SLOT_RELEASE_COMMAND\"' EXIT",
            ].joined(separator: "\n") + "\n"
        }
        try FileManager.default.createDirectory(atPath: claimDirectory, withIntermediateDirectories: true)
        try slotScript(takingOver: true, claim: claimDirectory + "/taken-over/.slot-claim")
            .write(toFile: claimDirectory + "/taken-over.sh", atomically: true, encoding: .utf8)
        try slotScript(takingOver: false, claim: claimDirectory + "/replaced/.slot-claim")
            .write(toFile: claimDirectory + "/replaced.sh", atomically: true, encoding: .utf8)

        let claims = try await laneBash(
            "mkdir -p '\(claimDirectory)/taken-over/.slot-claim' '\(claimDirectory)/replaced/.slot-claim'; "
                + "bash '\(claimDirectory)/taken-over.sh'; bash '\(claimDirectory)/replaced.sh'; "
                + "for slot in taken-over replaced; do "
                + "[ -d \"\(claimDirectory)/$slot/.slot-claim\" ] && echo \"$slot=leaked\" || echo \"$slot=released\"; done"
        )

        #expect(invocationExit.contains("eval \"$LANE_SLOT_RELEASE_COMMAND\""))
        #expect(lines(claims) == ["taken-over=released", "replaced=leaked"])
    }

    @Test("a hung test process gets a concurrency task dump before it is terminated")
    func hungTestProcessGetsTaskDumpBeforeTermination() async throws {
        // The fake child carries the test-bundle name so the runner selects it
        // for stack capture, then stalls without output like a wedged suite.
        let workDirectory = NSTemporaryDirectory() + "agentstudio-receipt-dump-\(UUIDv7.generate())"
        defer { try? FileManager.default.removeItem(atPath: workDirectory) }

        let laneOutput = try await laneBashAllowingFailure(
            "mkdir -p '\(workDirectory)'; "
                + "LOG_PREFIX=lane; TIMEOUT_SECONDS=2; BUILD_PATH=.build-agent-1; "
                + "export LANE_EVENT_STREAM_DIR='\(workDirectory)/ci-runs'; "
                + "source scripts/swift-test-helpers.sh; set +e; "
                + "run_swift_with_timeout 'dump probe' 2 /bin/bash -c "
                + "'while true; do sleep 1; done' AgentStudioPackageTests "
                + "|| returned=$?; echo \"RETURNED=${returned:-0}\""
        )
        let dumpRange = try #require(laneOutput.range(of: "lane-report task_dump="))
        let reapRange = try #require(laneOutput.range(of: "lane-report timeout_reap="))

        #expect(laneOutput.contains("RETURNED=124"))
        // bash is not a Swift process swift-inspect may attach to, so the dump
        // is refused, and the refusal is recorded instead of failing the lane.
        #expect(laneOutput.contains("lane-report task_dump=unavailable pid="))
        #expect(laneOutput.contains("reason="))
        // Taken while the process is still stuck, not after the reap.
        #expect(dumpRange.lowerBound < reapRange.lowerBound)
    }

    @Test("a task dump is kept beside the ledger, and a refused attach is recorded with its reason")
    func taskDumpIsKeptBesideLedgerAndRefusalIsRecorded() async throws {
        // swift-inspect exits 0 when it cannot attach, printing only to stderr, so
        // both fakes exit 0 and only the dump's content tells them apart.
        let workDirectory = NSTemporaryDirectory() + "agentstudio-receipt-inspect-\(UUIDv7.generate())"
        defer { try? FileManager.default.removeItem(atPath: workDirectory) }
        let attachingTool = workDirectory + "/attaching"
        let refusingTool = workDirectory + "/refusing"
        let fakeInspectors =
            "mkdir -p '\(attachingTool)' '\(refusingTool)'; "
            + "printf '#!/bin/bash\\necho TASKS; echo \"  Task 1 async backtrace: parkForever()\"\\n' "
            + "> '\(attachingTool)/xcrun'; "
            + "printf '#!/bin/bash\\necho \"unable to get task for pid $3: (os/kern) failure 0x5\" >&2; "
            + "echo \"Failed to create inspector for process id $3\" >&2\\n' > '\(refusingTool)/xcrun'; "
            + "chmod +x '\(attachingTool)/xcrun' '\(refusingTool)/xcrun'; "

        let attached = try await laneBash(
            fakeInspectors
                + "LOG_PREFIX=lane; export LANE_EVENT_STREAM_DIR='\(workDirectory)/ci-runs'; "
                + "source scripts/swift-test-helpers.sh; "
                + "PATH='\(attachingTool)':$PATH dump_stuck_swift_test_process_tasks 'dump probe' 4242; "
                + "for dump in '\(workDirectory)/ci-runs'/*.task-dump.txt; do cat \"$dump\"; done"
        )
        let refused = try await laneBash(
            fakeInspectors
                + "LOG_PREFIX=lane; export LANE_EVENT_STREAM_DIR='\(workDirectory)/refused-runs'; "
                + "source scripts/swift-test-helpers.sh; "
                + "PATH='\(refusingTool)':$PATH dump_stuck_swift_test_process_tasks 'dump probe' 4242; "
                + "echo \"DUMPS=$(ls -1 '\(workDirectory)/refused-runs' | wc -l | tr -d '[:space:]')\""
        )

        #expect(attached.contains("lane-report task_dump=\(workDirectory)/ci-runs/lane-dump-probe-"))
        #expect(attached.contains("-pid4242.task-dump.txt"))
        #expect(attached.contains("parkForever()"))
        #expect(
            refused.contains(
                "lane-report task_dump=unavailable pid=4242 reason=unable to get task for pid 4242: "
                    + "(os/kern) failure 0x5 Failed to create inspector for process id 4242"
            )
        )
        // A refused attach leaves no empty file posing as a dump.
        #expect(refused.contains("DUMPS=0"))
    }

    @Test("a crashed WebKit suite fails the lane once, named with its signal, and is never retried")
    func crashedWebKitSuiteFailsTheLaneWithoutRetry() async throws {
        // `swift test` reports a helper lost to a signal only as text and exits 1,
        // so the fake does exactly that and counts how often it was started.
        let workDirectory = NSTemporaryDirectory() + "agentstudio-receipt-webkit-\(UUIDv7.generate())"
        defer { try? FileManager.default.removeItem(atPath: workDirectory) }

        let laneOutput = try await laneBashAllowingFailure(
            "mkdir -p '\(workDirectory)/bin'; "
                + "printf '#!/bin/bash\\necho started >> \"\(workDirectory)/invocations\"\\n"
                + "echo \"error: Exited with unexpected signal code 11\"\\nexit 1\\n' > '\(workDirectory)/bin/swift'; "
                + "chmod +x '\(workDirectory)/bin/swift'; "
                + "export PATH='\(workDirectory)/bin':$PATH; "
                + "export SWIFT_TEST_FAILED_ISOLATED_SUITES_FILE='\(workDirectory)/tally'; "
                + ": > \"$SWIFT_TEST_FAILED_ISOLATED_SUITES_FILE\"; "
                + "LOG_PREFIX=webkit; TIMEOUT_SECONDS=60; BUILD_PATH=.build-agent-1; "
                + "export LANE_EVENT_STREAM_DIR='\(workDirectory)/ci-runs'; "
                + "source scripts/swift-test-helpers.sh; set +e; "
                + "webkit_suite_filters() { printf 'WebKitSerializedTests/CrashingSuite\\n"
                + "WebKitSerializedTests/NeverReachedSuite\\n'; }; "
                + "run_webkit_suites; echo \"LANE_STATUS=$?\"; "
                + "echo \"INVOCATIONS=$(wc -l < '\(workDirectory)/invocations' | tr -d '[:space:]')\"; "
                + "cat \"$SWIFT_TEST_FAILED_ISOLATED_SUITES_FILE\""
        )

        #expect(laneOutput.contains("LANE_STATUS=1"))
        // Exactly one start: no in-lane retry of the crashed suite, and the lane
        // stops there rather than reporting green later.
        #expect(laneOutput.contains("INVOCATIONS=1"))
        #expect(
            laneOutput.contains("WebKit suite failed: WebKitSerializedTests/CrashingSuite status=1 signal=SEGV")
        )
        #expect(laneOutput.contains("WebKitSerializedTests/CrashingSuite\t1\tSEGV"))
        #expect(!laneOutput.contains("retrying"))
    }

    @Test("crash signals are read from the status or from swift test's own report")
    func crashSignalsAreReadFromStatusOrSwiftTestReport() async throws {
        let names = try await laneBash(
            "source scripts/swift-test-helpers.sh; "
                + "swift_test_crash_signal_name 139 ''; "
                + "swift_test_crash_signal_name 1 'error: Exited with unexpected signal code 5'; "
                + "swift_test_crash_signal_name 1 'Test run with 2 tests failed'; "
                + "swift_test_crash_signal_name 124 ''"
        )

        #expect(lines(names) == ["SEGV", "TRAP", "none", "none"])
    }

    @Test("the width comparison runs both halves on one bundle and keeps every ledger")
    func widthComparisonRunsBothHalvesOnOneBundleAndKeepsEveryLedger() async throws {
        let laneRunnerScript = try String(contentsOfFile: "scripts/run-swift-test-task.sh", encoding: .utf8)
        let miseConfig = try String(contentsOfFile: ".mise.toml", encoding: .utf8)
        let comparison = try laneScriptShellFunction(named: "run_width_comparison", in: laneRunnerScript)
        let half = try laneScriptShellFunction(named: "run_width_comparison_half", in: laneRunnerScript)
        let comparisonTask = try laneScriptNamedBlock(
            startingWith: "[tasks.\"test:swift:width-comparison\"]",
            endingBefore: "\n[tasks.",
            in: miseConfig
        )
        let workDirectory = NSTemporaryDirectory() + "agentstudio-receipt-retain-\(UUIDv7.generate())"
        defer { try? FileManager.default.removeItem(atPath: workDirectory) }

        let retained = try await laneBash(
            "LOG_PREFIX=lane; TIMEOUT_SECONDS=60; BUILD_PATH=.build-agent-1; "
                + "export LANE_EVENT_STREAM_DIR='\(workDirectory)'; LANE_EVENT_STREAM_RETAIN_ALWAYS=1; "
                + "source scripts/swift-test-helpers.sh; "
                + "run_swift_with_timeout 'clean half' 60 /bin/bash -c 'echo CLEAN_RUN_OK'; "
                + "echo \"LEDGERS=$(ls -1 '\(workDirectory)' | wc -l | tr -d '[:space:]')\""
        )

        #expect(comparisonTask.contains("run = \"/bin/bash scripts/run-swift-test-task.sh test-width-comparison\""))
        // Width 3 is the CI runner's core count; the other half leaves it unset.
        #expect(comparison.contains("run_width_comparison_half 3 \"$comparison_directory/width-3\""))
        #expect(comparison.contains("run_width_comparison_half \"\" \"$comparison_directory/width-unlimited\""))
        // One bundle for both halves: the comparison never builds, and its
        // directory is named for the bundle both halves share.
        #expect(!comparison.contains("prebuild_swift_tests"))
        #expect(!half.contains("prebuild_swift_tests"))
        #expect(comparison.contains("-bundle-${bundle_identity##*@}"))
        // Each half is a lane of its own: opening receipt, closing receipt on
        // EXIT, forced ledger retention, and its whole output kept.
        #expect(
            half.contains(
                "print_opening_lane_report\n    begin_lane_accounting\n    trap print_closing_lane_report EXIT"
            )
        )
        #expect(half.contains("LANE_EVENT_STREAM_RETAIN_ALWAYS=1"))
        #expect(half.contains("unset SWIFT_TEST_PARALLELIZATION_WIDTH"))
        #expect(half.contains("tee \"$ledger_directory/lane-output.log\""))
        // A passing run keeps its ledger when retention is forced.
        #expect(retained.contains("CLEAN_RUN_OK"))
        #expect(retained.contains("lane-report event_stream=\(workDirectory)/lane-clean-half-"))
        #expect(retained.contains("LEDGERS=1"))
    }
}

private func lines(_ output: String) -> [String] {
    output.split(separator: "\n").map(String.init)
}

private func laneBash(_ command: String) async throws -> String {
    let result = try await runLaneScriptBash(command)
    #expect(result.exitCode == 0, Comment(rawValue: result.output))
    return result.output
}

/// For scripts that deliberately fail: these tests drive crashing and hung
/// children, so a non-zero status is the expected outcome.
private func laneBashAllowingFailure(_ command: String) async throws -> String {
    (try await runLaneScriptBash(command)).output
}
