import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@Suite("Swift lane runner load reporting")
struct SwiftLaneRunnerReportTests {
    @Test("every Swift test invocation takes its parallelization width from the one helper")
    func everySwiftTestInvocationTakesItsWidthFromTheOneHelper() throws {
        let helperScript = try String(contentsOfFile: "scripts/swift-test-helpers.sh", encoding: .utf8)
        let laneRunnerScript = try String(contentsOfFile: "scripts/run-swift-test-task.sh", encoding: .utf8)
        let widthFunction = try shellFunction(named: "swift_test_parallelization_width", in: helperScript)
        let invocationLines = (helperScript + "\n" + laneRunnerScript)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.contains("env AGENT_STUDIO_BENCHMARK_MODE=off") }
        let invocationsBypassingTheHelper = invocationLines.filter {
            !$0.contains("$(swift_test_parallelization_env_word)")
        }

        #expect(invocationLines.count >= 10)
        #expect(
            invocationsBypassingTheHelper.isEmpty,
            "Swift test invocations not routed through the width helper: \(invocationsBypassingTheHelper)"
        )
        // No default: the cap is experimental, and a set width hung this suite at
        // every width tried, so it must stay opt-in.
        #expect(widthFunction.contains("${SWIFT_TEST_PARALLELIZATION_WIDTH:-}"))
        #expect(!widthFunction.contains("hw.ncpu"))
        // No call site may name the variable directly; that is how they drift.
        #expect(
            invocationLines.allSatisfy {
                !$0.contains("SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=")
            }
        )
    }

    @Test("the width reaches the environment only when it is set")
    func widthReachesTheEnvironmentOnlyWhenItIsSet() async throws {
        // Absence and empty are different to Swift Testing: absence means
        // unlimited, and we never want to depend on how it parses "" or 0.
        let unsetWord = try await runBash(
            "env -u SWIFT_TEST_PARALLELIZATION_WIDTH bash -c "
                + "'source scripts/swift-test-helpers.sh; swift_test_parallelization_env_word'"
        )
        let setWord = try await runBash(
            "SWIFT_TEST_PARALLELIZATION_WIDTH=7 bash -c "
                + "'source scripts/swift-test-helpers.sh; swift_test_parallelization_env_word'"
        )
        // The word is used unquoted, so an empty helper must contribute no
        // argument at all to the invocation.
        let unsetArgumentCount = try await runBash(
            "env -u SWIFT_TEST_PARALLELIZATION_WIDTH bash -c "
                + "'source scripts/swift-test-helpers.sh; "
                + "set -- $(swift_test_parallelization_env_word); echo $#'"
        )
        let unsetLabel = try await runBash(
            "env -u SWIFT_TEST_PARALLELIZATION_WIDTH bash -c "
                + "'source scripts/swift-test-helpers.sh; swift_test_parallelization_width_label'"
        )
        let setLabel = try await runBash(
            "SWIFT_TEST_PARALLELIZATION_WIDTH=7 bash -c "
                + "'source scripts/swift-test-helpers.sh; swift_test_parallelization_width_label'"
        )

        #expect(unsetWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(
            setWord.trimmingCharacters(in: .whitespacesAndNewlines)
                == "SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=7"
        )
        #expect(unsetArgumentCount.trimmingCharacters(in: .whitespacesAndNewlines) == "0")
        #expect(unsetLabel.trimmingCharacters(in: .whitespacesAndNewlines) == "unlimited")
        #expect(setLabel.trimmingCharacters(in: .whitespacesAndNewlines) == "7")
    }

    @Test("lane runner reports machine load before and after every lane")
    func laneRunnerReportsMachineLoadBeforeAndAfterEveryLane() throws {
        let helperScript = try String(contentsOfFile: "scripts/swift-test-helpers.sh", encoding: .utf8)
        let laneRunnerScript = try String(contentsOfFile: "scripts/run-swift-test-task.sh", encoding: .utf8)
        let closingReport = try shellFunction(named: "print_closing_lane_report", in: laneRunnerScript)

        for preflightLabel in [
            "lane-report cpu_count=",
            "lane-report memory_bytes=",
            "lane-report parallelization_width=",
            "lane-report isolated_process_concurrency=",
            "lane-report xcode=",
            "lane-report swift=",
            "lane-report head_sha=",
            "lane-report tree_dirty=",
        ] {
            #expect(laneRunnerScript.contains(preflightLabel))
        }
        for closingLabel in [
            "lane-report exit_status=",
            "lane-report wall_seconds=",
            "lane-report cpu_seconds=",
            "lane-report cpu_utilization=",
            "lane-report peak_announced_tests=",
            "lane-report peak_running_parameterized_cases=",
            "lane-report failed_isolated_suites=",
            "lane-report head_sha=",
            "lane-report tree_dirty=",
            "lane-report bundle_state=",
            "lane-report bundle_identity=",
            "lane-report build_receipt_head_sha=",
        ] {
            #expect(closingReport.contains(closingLabel))
        }
        // Validity and verdict are decided by one helper, so the receipt cannot
        // print a verdict that skipped the validity check.
        #expect(closingReport.contains("print_lane_receipt_verdict \"$exit_status\""))
        // The whole point of a stable prefix is that a CI reader can grep it, so
        // the emitted label set is pinned rather than only spot-checked.
        #expect(
            laneReportLabels(in: helperScript + "\n" + laneRunnerScript) == [
                // Which tree and bundle the lane tested, and whether that makes
                // its verdict evidence at all.
                "build_receipt_head_sha",
                "bundle_identity",
                "bundle_state",
                "cpu_count",
                "cpu_seconds",
                "cpu_utilization",
                // Where a wedged run's event-stream ledger was kept, and whether
                // the lane's own child group was actually reaped on the way out.
                "event_stream",
                "exit_status",
                "failed_isolated_suite",
                "failed_isolated_suites",
                "head_sha",
                "isolated_process_concurrency",
                "memory_bytes",
                "parallelization_width",
                // Tests whose start was posted: announced, never "started".
                "peak_announced_tests",
                "peak_running_parameterized_cases",
                "receipt_valid",
                "running_parameterized_cases_at_timeout",
                "swift",
                "task_dump",
                "timeout_reap",
                "tree_dirty",
                "verdict",
                "wall_seconds",
                "xcode",
            ]
        )
        // A failing lane is the one whose load numbers matter most, so the
        // closing block hangs off EXIT rather than the end of the happy path.
        let invocationExit = try shellFunction(named: "finish_lane_invocation", in: laneRunnerScript)
        #expect(laneRunnerScript.contains("trap finish_lane_invocation EXIT"))
        #expect(invocationExit.hasPrefix("finish_lane_invocation() {\n  print_closing_lane_report\n"))
    }

    @Test("a child that dies by signal is named instead of swallowed")
    func childThatDiesBySignalIsNamedInsteadOfSwallowed() async throws {
        // A process that passes its tests and then crashes used to leave only
        // "ERROR task failed" and bash's job-table line; the captured output was
        // deleted before anyone could read why.
        let laneOutput = try await runBashAllowingFailure(
            "LOG_PREFIX=lane; TIMEOUT_SECONDS=60; BUILD_PATH=.build-agent-1; "
                + "source scripts/swift-test-helpers.sh; set +e; "
                + "run_swift_with_timeout 'isolated suite: FakeSuite' 60 /bin/bash -c "
                + #"'echo \"Test run with 1 test in 1 suite passed\"; kill -SEGV $$' "#
                + "|| returned=$?; echo \"RETURNED=${returned:-0}\""
        )

        #expect(laneOutput.contains("exit_status=139"))
        #expect(laneOutput.contains("signal=SEGV"))
        #expect(laneOutput.contains("raw output tail for 'isolated suite: FakeSuite'"))
        // The tail is the point: the child's own output survives to the log.
        #expect(laneOutput.contains("Test run with 1 test in 1 suite passed"))
        #expect(laneOutput.contains("RETURNED=139"))
    }

    @Test("signal names are resolved only for signalled exits")
    func signalNamesAreResolvedOnlyForSignalledExits() async throws {
        let names = try await runBash(
            "source scripts/swift-test-helpers.sh; "
                + "swift_test_signal_name 139; swift_test_signal_name 133; "
                + "swift_test_signal_name 1; swift_test_signal_name 0"
        )
        .split(separator: "\n").map(String.init)

        #expect(names == ["SEGV", "TRAP", "none", "none"])
    }

    @Test("one crashed isolated suite does not hide the suites after it")
    func oneCrashedIsolatedSuiteDoesNotHideTheSuitesAfterIt() async throws {
        // Two batched children: the first crashes, the second must still run and
        // still be observable. Stopping at the first is what hid 324 of 336
        // suites behind one crash.
        let tallyPath = NSTemporaryDirectory() + "agentstudio-s2d-tally-\(UUIDv7.generate())"
        defer { try? FileManager.default.removeItem(atPath: tallyPath) }
        let laneOutput = try await runBashAllowingFailure(
            "LOG_PREFIX=lane; export SWIFT_TEST_FAILED_ISOLATED_SUITES_FILE='\(tallyPath)'; "
                + ": >\"$SWIFT_TEST_FAILED_ISOLATED_SUITES_FILE\"; "
                + "source scripts/swift-test-helpers.sh; set +e; "
                + "/bin/bash -c 'kill -SEGV $$' & first=$!; "
                + "/bin/bash -c 'echo SECOND_BATCH_RAN; exit 0' & second=$!; "
                + "batch=0; "
                + "wait_for_process_global_suite_batch \"$first\" CrashingSuite \"$second\" HealthySuite "
                + "|| batch=$?; echo \"BATCH=$batch\"; "
                + "echo \"COUNT=$(swift_test_failed_isolated_suite_count)\"; "
                + "cat \"$SWIFT_TEST_FAILED_ISOLATED_SUITES_FILE\""
        )

        // Both children ran; only the crashing one is recorded.
        #expect(laneOutput.contains("SECOND_BATCH_RAN"))
        #expect(laneOutput.contains("isolated suite failed: CrashingSuite"))
        #expect(!laneOutput.contains("isolated suite failed: HealthySuite"))
        #expect(laneOutput.contains("BATCH=1"))
        #expect(laneOutput.contains("COUNT=1"))
        #expect(laneOutput.contains("CrashingSuite\t139\tSEGV"))
    }

    @Test("a timed out child that ignores TERM is still reaped, and the report is still written")
    func timedOutChildThatIgnoresTermIsStillReaped() async throws {
        // The shape that survived the old parent-link walk: a child that traps
        // TERM, so only a group-wide KILL removes it. One of these left alive
        // holds a build slot, and the NEXT run dies with "all 2 slots are busy",
        // which reads like an unrelated slot error rather than this timeout.
        let workDirectory = NSTemporaryDirectory() + "agentstudio-s2e-reap-\(UUIDv7.generate())"
        defer { try? FileManager.default.removeItem(atPath: workDirectory) }
        let laneOutput = try await runBashAllowingFailure(
            "mkdir -p '\(workDirectory)'; "
                + "LOG_PREFIX=lane; TIMEOUT_SECONDS=2; BUILD_PATH=.build-agent-1; "
                + "export LANE_EVENT_STREAM_DIR='\(workDirectory)/ci-runs'; "
                + "source scripts/swift-test-helpers.sh; set +e; "
                + "run_swift_with_timeout 'reap probe' 2 /bin/bash -c "
                + #"'trap \"\" TERM; echo $$ > \"$0\"/child.pid; while true; do sleep 1; done' "#
                + "'\(workDirectory)' "
                + "|| returned=$?; echo \"RETURNED=${returned:-0}\"; "
                + "child_pid=$(cat '\(workDirectory)/child.pid' 2>/dev/null || echo 0); "
                + "if [ \"$child_pid\" -gt 0 ] && kill -0 \"$child_pid\" 2>/dev/null; then "
                + "echo CHILD_ALIVE=yes; kill -9 \"$child_pid\" 2>/dev/null; "
                + "else echo CHILD_ALIVE=no; fi"
        )

        // The reap is the point: nothing of the lane's child outlives the timeout.
        #expect(laneOutput.contains("CHILD_ALIVE=no"))
        // And it took the KILL branch, because this child ignores TERM. Asserting
        // the exact branch keeps the test honest: a child that happened to exit on
        // its own would report `terminated` and prove nothing about the escalation.
        #expect(laneOutput.contains("timeout_reap=killed"))
        // And the report still happens — reaping must not cost the diagnosis.
        #expect(laneOutput.contains("ERROR: no output progress from 'reap probe'"))
        #expect(laneOutput.contains("RETURNED=124"))
    }

    @Test("a grandchild that outlives its parent is still reaped")
    func grandchildThatOutlivesItsParentIsStillReaped() async throws {
        // The real defect. The parent honours TERM and dies; its child ignores
        // TERM and re-parents, so it is no longer reachable by walking live parent
        // links from the lane's own pid. That survivor is the `swiftpm-testing-helper`
        // that kept holding a build slot and made the next run fail with
        // "all 2 slots are busy". Only this run's unique event-stream path can
        // still find it — which is why the KILL path sweeps that token.
        let workDirectory = NSTemporaryDirectory() + "agentstudio-s2e-orphan-\(UUIDv7.generate())"
        defer { try? FileManager.default.removeItem(atPath: workDirectory) }
        let laneOutput = try await runBashAllowingFailure(
            "mkdir -p '\(workDirectory)'; "
                + "LOG_PREFIX=lane; TIMEOUT_SECONDS=2; BUILD_PATH=.build-agent-1; "
                + "export LANE_EVENT_STREAM_DIR='\(workDirectory)/ci-runs'; "
                + "source scripts/swift-test-helpers.sh; set +e; "
                + "run_swift_with_timeout 'orphan probe' 2 /bin/bash -c "
                // The subshell inherits this invocation's argv, so it carries the
                // event-stream path the runner appended — the token that finds it.
                // The PARENT records the pid with `$!` and only then exits, so the
                // pid is on disk before anything can race it. Writing it from
                // inside the subshell lost the race against `exit 0`, and reading
                // `$$` there would have recorded the parent instead — either way
                // the liveness check below would have passed vacuously.
                // `trap : TERM` installs a no-op handler without needing nested
                // quotes.
                + "'( trap : TERM; while true; do sleep 1; done ) & "
                + "echo $! > \(workDirectory)/orphan.pid; exit 0' "
                + "|| returned=$?; echo \"RETURNED=${returned:-0}\"; "
                + "orphan_pid=$(cat '\(workDirectory)/orphan.pid' 2>/dev/null || echo 0); "
                + "echo \"ORPHAN_PID=${orphan_pid:-0}\"; "
                + "if [ \"${orphan_pid:-0}\" -gt 0 ] && kill -0 \"$orphan_pid\" 2>/dev/null; then "
                + "echo ORPHAN_ALIVE=yes; kill -9 \"$orphan_pid\" 2>/dev/null; "
                + "else echo ORPHAN_ALIVE=no; fi"
        )

        // The probe must actually have produced an orphan, or "no survivor" below
        // would be true for the wrong reason.
        #expect(!laneOutput.contains("ORPHAN_PID=0"))
        // Nothing of this run outlives the lane, however it re-parented.
        #expect(laneOutput.contains("ORPHAN_ALIVE=no"))
        #expect(laneOutput.contains("timeout_reap=killed"))
        #expect(laneOutput.contains("RETURNED=124"))
    }

    @Test("a wedged run keeps its event-stream ledger, and a clean run does not")
    func wedgedRunKeepsItsEventStreamLedger() async throws {
        // The ledger is the only authoritative record of which cases started and
        // ended. Without it the same wedged runs produced two contradictory
        // unfinished-suite counts from console archaeology.
        let workDirectory = NSTemporaryDirectory() + "agentstudio-s2e-ledger-\(UUIDv7.generate())"
        defer { try? FileManager.default.removeItem(atPath: workDirectory) }
        let ledgerDirectory = workDirectory + "/ci-runs"
        // The child writes real records to the path the runner handed it, then
        // stalls without output, which is exactly how a wedged suite behaves.
        let wedgedOutput = try await runBashAllowingFailure(
            "mkdir -p '\(workDirectory)'; "
                + "LOG_PREFIX=lane; TIMEOUT_SECONDS=2; BUILD_PATH=.build-agent-1; "
                + "export LANE_EVENT_STREAM_DIR='\(ledgerDirectory)'; "
                + "source scripts/swift-test-helpers.sh; set +e; "
                + "run_swift_with_timeout 'ledger probe' 2 /bin/bash -c "
                + #"'while [ \"$#\" -gt 0 ]; do if [ \"$1\" = \"--event-stream-output-path\" ]; "#
                + #"then printf \"%s\\n\" LEDGER_RECORD_ONE LEDGER_RECORD_TWO > \"$2\"; fi; shift; done; "#
                + #"while true; do sleep 1; done' probe "#
                + "|| returned=$?; echo \"RETURNED=${returned:-0}\"; "
                + "for ledger in '\(ledgerDirectory)'/*.events.jsonl; do "
                + "echo \"LEDGER_AT=$ledger\"; cat \"$ledger\"; done"
        )

        #expect(wedgedOutput.contains("RETURNED=124"))
        // The path is printed under the lane prefix so a reader can find it.
        #expect(wedgedOutput.contains("lane-report event_stream=\(ledgerDirectory)/lane-ledger-probe-"))
        // ...and the records survived the reap.
        #expect(wedgedOutput.contains("LEDGER_RECORD_ONE"))
        #expect(wedgedOutput.contains("LEDGER_RECORD_TWO"))

        let cleanDirectory = workDirectory + "/clean-runs"
        let cleanOutput = try await runBash(
            "LOG_PREFIX=lane; TIMEOUT_SECONDS=60; BUILD_PATH=.build-agent-1; "
                + "export LANE_EVENT_STREAM_DIR='\(cleanDirectory)'; "
                + "source scripts/swift-test-helpers.sh; "
                + "run_swift_with_timeout 'clean probe' 60 /bin/bash -c 'echo CLEAN_RUN_OK'; "
                + "echo \"LEDGERS=$(ls -1 '\(cleanDirectory)' 2>/dev/null | wc -l | tr -d '[:space:]')\""
        )

        // A run that ended cleanly has nothing to explain, so it keeps nothing.
        #expect(cleanOutput.contains("CLEAN_RUN_OK"))
        #expect(cleanOutput.contains("LEDGERS=0"))
    }

    @Test("an isolated suite filter matches its type, never a file named after it")
    func isolatedSuiteFilterMatchesItsTypeNeverAFileNamedAfterIt() async throws {
        // Real ids captured from an event stream on this bundle. The third belongs
        // to a DIFFERENT suite that merely lives in RepoScannerTests.swift, and the
        // bare name selected it too: `--filter RepoScannerTests` admitted 2 suites
        // and 29 ids. Two process-global suites sharing one process is what
        // SIGSEGVed in CI 35276671883.
        let suiteIdentifier = "AgentStudioInfrastructureTests.RepoScannerTests"
        let ownFunctionIdentifier =
            "AgentStudioInfrastructureTests.RepoScannerTests/"
            + "cloneRootGitdirIndirectionsOutsideScannedPathAreFilteredOut()/RepoScannerTests.swift:234:6"
        let siblingIdentifier =
            "AgentStudioInfrastructureTests.RepoScannerClassificationTests/"
            + "gitDirectoryIsCloneRoot()/RepoScannerTests.swift:430:6"

        let matches = try await runBash(
            "source scripts/swift-test-helpers.sh; "
                + "pattern=$(swift_test_isolated_suite_filter_pattern RepoScannerTests); "
                + "echo \"PATTERN=$pattern\"; "
                + "for id in '\(suiteIdentifier)' '\(ownFunctionIdentifier)' '\(siblingIdentifier)'; do "
                + "if printf '%s' \"$id\" | /usr/bin/grep -Eq \"$pattern\"; "
                + "then echo MATCH; else echo NOMATCH; fi; done"
        )
        .split(separator: "\n").map(String.init)

        #expect(matches.first == "PATTERN=\\.RepoScannerTests(/|$)")
        // The suite's own id and its own functions are selected...
        #expect(matches.dropFirst().first == "MATCH")
        #expect(matches.dropFirst(2).first == "MATCH")
        // ...and the neighbour sharing the source file is not.
        #expect(matches.dropFirst(3).first == "NOMATCH")
    }

    @Test("every isolated per-process invocation anchors its suite filter")
    func everyIsolatedPerProcessInvocationAnchorsItsSuiteFilter() throws {
        let helperScript = try String(contentsOfFile: "scripts/swift-test-helpers.sh", encoding: .utf8)

        // The three places that start one process for one suite must all go
        // through the helper; a bare name at any of them reopens the crash.
        #expect(
            helperScript.contains(
                "--filter \"$(swift_test_isolated_suite_filter_pattern \"$aggregate_serial_suite_filter\")\""
            ))
        #expect(
            helperScript.contains(
                "--filter \"$(swift_test_isolated_suite_filter_pattern \"$large_process_global_suite_filter\")\""
            ))
        #expect(
            helperScript.contains(
                "--filter \"$(swift_test_isolated_suite_filter_pattern \"$(fast_serial_process_filter_pattern)\")\""
            ))
        // The fast lane's skip is the mirror of the same defect.
        #expect(helperScript.contains("--skip \"$(fast_non_webkit_skip_pattern)\""))
        // Substring families must NOT be anchored: they match many suites by
        // prefix, and anchoring them would drop whole suites out of their lane.
        let skipBuilder = try shellFunction(named: "fast_non_webkit_skip_pattern", in: helperScript)
        #expect(skipBuilder.contains("\"$(large_non_webkit_filter_pattern)\""))
        #expect(!skipBuilder.contains("swift_test_isolated_suite_skip_pattern \"$(large_non_webkit_filter_pattern)\""))
    }

    @Test("a clean lane reports zero failed isolated suites")
    func cleanLaneReportsZeroFailedIsolatedSuites() async throws {
        let count = try await runBash(
            "source scripts/swift-test-helpers.sh; swift_test_failed_isolated_suite_count"
        )

        // No tally file exported at all is the clean-lane case.
        #expect(count.trimmingCharacters(in: .whitespacesAndNewlines) == "0")
    }

    @Test("the inactivity timeout names the test cases that were still running")
    func inactivityTimeoutNamesTheTestCasesThatWereStillRunning() async throws {
        let helperScript = try String(contentsOfFile: "scripts/swift-test-helpers.sh", encoding: .utf8)
        let timeoutRunner = try shellFunction(named: "run_swift_with_timeout", in: helperScript)
        // Case 1 of alpha ends; case 2 and beta do not, and the truncated final
        // line a killed writer leaves behind must not derail the parse.
        let streamRecords = [
            #"{\"kind\":\"testCaseStarted\",\"testID\":\"S/alpha(v:)\",\"_testCase\":{\"displayName\":\"v: 1\"}}"#,
            #"{\"kind\":\"testCaseStarted\",\"testID\":\"S/alpha(v:)\",\"_testCase\":{\"displayName\":\"v: 2\"}}"#,
            #"{\"kind\":\"testCaseEnded\",\"testID\":\"S/alpha(v:)\",\"_testCase\":{\"displayName\":\"v: 1\"}}"#,
            #"{\"kind\":\"testCaseStarted\",\"testID\":\"S/beta()\"}"#,
            #"{\"kind\":\"testCase"#,
        ].joined(separator: #"\n"#)
        let stillRunning = try await runBash(
            "LOG_PREFIX=lane; source scripts/swift-test-helpers.sh; "
                + "print_running_parameterized_cases_at_timeout <(printf '\(streamRecords)\\n')"
        )
        let withoutStream = try await runBash(
            "LOG_PREFIX=lane; source scripts/swift-test-helpers.sh; "
                + "print_running_parameterized_cases_at_timeout /nonexistent/event-stream"
        )
        let emptyStream = try await runBash(
            "LOG_PREFIX=lane; source scripts/swift-test-helpers.sh; "
                + "print_running_parameterized_cases_at_timeout /dev/null"
        )

        #expect(timeoutRunner.contains("print_running_parameterized_cases_at_timeout \"$event_stream_file\""))
        #expect(
            stillRunning.split(separator: "\n").map(String.init) == [
                "[lane] lane-report running_parameterized_cases_at_timeout=S/alpha(v:) [v: 2]",
                "[lane] lane-report running_parameterized_cases_at_timeout=S/beta()",
            ]
        )
        // Missing stream and empty stream are different findings, so they read
        // differently rather than both looking like "nothing was running".
        #expect(withoutStream.contains("running_parameterized_cases_at_timeout=unavailable"))
        #expect(emptyStream.contains("running_parameterized_cases_at_timeout=none"))
    }

    @Test("the at-timeout case list is capped so one wedged lane cannot bury its log")
    func atTimeoutCaseListIsCappedSoOneWedgedLaneCannotBuryItsLog() async throws {
        let helperScript = try String(contentsOfFile: "scripts/swift-test-helpers.sh", encoding: .utf8)
        let idsFunction = try shellFunction(named: "swift_test_running_case_ids_from_events", in: helperScript)
        let cappedIDs = try await runBash(
            "source scripts/swift-test-helpers.sh; swift_test_running_case_ids_from_events "
                + #"<(for index in $(seq 1 60); do printf '{"kind":"testCaseStarted","testID":"S/t%s()"}\n' "$index"; done)"#
        )

        #expect(idsFunction.contains("maximum_ids=\"${2:-40}\""))
        #expect(cappedIDs.split(separator: "\n").count == 40)
    }

    @Test("lane runner hang bounds default to the budgets CI already sets")
    func laneRunnerHangBoundsDefaultToBudgetsCIAlreadySets() throws {
        let laneRunnerScript = try String(contentsOfFile: "scripts/run-swift-test-task.sh", encoding: .utf8)
        let ciWorkflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)
        let prebuildStep = try workflowStep(named: "Prebuild Swift test bundles", in: ciWorkflow)

        #expect(laneRunnerScript.contains("TIMEOUT_SECONDS=\"${SWIFT_TEST_TIMEOUT_SECONDS:-600}\""))
        #expect(
            laneRunnerScript.contains(
                "PREBUILD_TIMEOUT_SECONDS=\"${SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS:-1200}\""
            )
        )
        #expect(!laneRunnerScript.contains(":-60}"))
        #expect(!laneRunnerScript.contains(":-90}"))
        #expect(prebuildStep.contains("SWIFT_TEST_TIMEOUT_SECONDS: \"600\""))
        #expect(prebuildStep.contains("SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS: \"1200\""))
    }

    @Test("isolated suite process fan-out never exceeds the core count")
    func isolatedSuiteProcessFanOutNeverExceedsCoreCount() async throws {
        let helperScript = try String(contentsOfFile: "scripts/swift-test-helpers.sh", encoding: .utf8)
        let concurrencyFunction = try shellFunction(
            named: "swift_test_isolated_process_concurrency",
            in: helperScript
        )
        let observedConcurrency = try await runBash(
            "source scripts/swift-test-helpers.sh; swift_test_isolated_process_concurrency"
        )
        let reportedCoreCount = try await runBash("sysctl -n hw.ncpu")
        let concurrency = try #require(
            Int(observedConcurrency.trimmingCharacters(in: .whitespacesAndNewlines))
        )
        let coreCount = try #require(
            Int(reportedCoreCount.trimmingCharacters(in: .whitespacesAndNewlines))
        )

        #expect(concurrencyFunction.contains("sysctl -n hw.ncpu"))
        #expect(concurrency == min(4, coreCount))
        #expect(concurrency >= 1)
    }

    @Test("announced-test counter tracks posted start events, not the cap")
    func announcedTestCounterTracksPostedStartEvents() async throws {
        // a and b overlap (peak 2), a closes, then c opens (2 again). The
        // run-level and suite-level events are not tests.
        let observedPeak = try await runBash(
            "source scripts/swift-test-helpers.sh; swift_test_peak_announced_from_output "
                + "<(printf '◇ Test run started.\\n"
                + "◇ Suite \"S\" started.\\n"
                + "◇ Test \"a\" started.\\n"
                + "◇ Test \"b\" started.\\n"
                + "✔ Test \"a\" passed after 0.1 seconds.\\n"
                + "◇ Test \"c\" started.\\n"
                + "✔ Test run with 3 tests in 1 suite passed after 0.5 seconds.\\n')"
        )

        #expect(observedPeak.trimmingCharacters(in: .whitespacesAndNewlines) == "2")
    }

    @Test("running-test-case counter reads the post-serializer event stream")
    func runningTestCaseCounterReadsPostSerializerEventStream() async throws {
        // Two cases overlap before either ends, so the cap-observing peak is 2.
        let observedPeak = try await runBash(
            "source scripts/swift-test-helpers.sh; swift_test_peak_running_cases_from_events "
                + "<(printf '{\"kind\":\"testCaseStarted\"}\\n"
                + "{\"kind\":\"testCaseStarted\"}\\n"
                + "{\"kind\":\"testCaseEnded\"}\\n"
                + "{\"kind\":\"testCaseStarted\"}\\n"
                + "{\"kind\":\"testCaseEnded\"}\\n"
                + "{\"kind\":\"testCaseEnded\"}\\n')"
        )
        let emptyStreamPeak = try await runBash(
            "source scripts/swift-test-helpers.sh; swift_test_peak_running_cases_from_events /dev/null"
        )

        #expect(observedPeak.trimmingCharacters(in: .whitespacesAndNewlines) == "2")
        #expect(emptyStreamPeak.trimmingCharacters(in: .whitespacesAndNewlines) == "0")
    }

    @Test("event-stream flags reach every test invocation but not the prebuild")
    func eventStreamFlagsReachEveryTestInvocationButNotThePrebuild() async throws {
        let helperScript = try String(contentsOfFile: "scripts/swift-test-helpers.sh", encoding: .utf8)
        let timeoutRunner = try shellFunction(named: "run_swift_with_timeout", in: helperScript)
        let acceptsEventStream = try shellFunction(
            named: "swift_test_command_accepts_event_stream",
            in: helperScript
        )

        #expect(timeoutRunner.contains("--event-stream-version 0 --event-stream-output-path"))
        #expect(timeoutRunner.contains("swift_test_command_accepts_event_stream"))
        // `swift build` rejects the flags, so the prebuild must be excluded.
        #expect(acceptsEventStream.contains("\"$argument\" = \"build\""))
        #expect(
            try await runBashStatus(
                "source scripts/swift-test-helpers.sh; "
                    + "swift_test_command_accepts_event_stream swift build --build-tests"
            ) == 1
        )
        #expect(
            try await runBashStatus(
                "source scripts/swift-test-helpers.sh; "
                    + "swift_test_command_accepts_event_stream swift test --skip-build"
            ) == 0
        )
    }
}

/// Every `lane-report <label>=` key the shell scripts can emit, sorted.
private func laneReportLabels(in script: String) -> [String] {
    let marker = "lane-report "
    var labels: Set<String> = []

    for line in script.split(separator: "\n") {
        guard let markerRange = line.range(of: marker) else { continue }
        let label = line[markerRange.upperBound...].prefix { $0.isLowercase || $0 == "_" }
        guard !label.isEmpty, line[markerRange.upperBound...].dropFirst(label.count).first == "=" else { continue }
        labels.insert(String(label))
    }
    return labels.sorted()
}

private func workflowStep(named stepName: String, in workflow: String) throws -> String {
    try namedBlock(
        startingWith: "      - name: \(stepName)",
        endingBefore: "\n      - name: ",
        in: workflow
    )
}

private func shellFunction(named functionName: String, in script: String) throws -> String {
    try namedBlock(
        startingWith: "\(functionName)() {",
        endingBefore: "\n}\n",
        in: script
    )
}

private func namedBlock(startingWith marker: String, endingBefore terminator: String, in text: String) throws
    -> String
{
    guard let startRange = text.range(of: marker) else {
        throw SwiftLaneRunnerReportError.missingBlock(marker)
    }
    let tail = text[startRange.lowerBound...]
    guard let endRange = tail.range(of: terminator, range: tail.index(after: startRange.lowerBound)..<tail.endIndex)
    else {
        return String(tail)
    }
    return String(tail[..<endRange.lowerBound])
}

private func runBash(_ command: String) async throws -> String {
    let result = try await runLaneScriptBash(command)
    #expect(result.exitCode == 0, Comment(rawValue: result.output))
    return result.output
}

/// Like `runBash`, but for scripts that deliberately fail: these tests drive
/// crashing children, so a non-zero status is the expected outcome.
private func runBashAllowingFailure(_ command: String) async throws -> String {
    (try await runLaneScriptBash(command)).output
}

private func runBashStatus(_ command: String) async throws -> Int32 {
    (try await runLaneScriptBash(command)).exitCode
}

private enum SwiftLaneRunnerReportError: Error {
    case missingBlock(String)
}
