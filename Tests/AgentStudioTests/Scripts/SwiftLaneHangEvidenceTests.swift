import AgentStudioInfrastructure
import Darwin
import Foundation
import Testing

/// What a hung lane leaves behind before it is terminated: a concurrency task
/// dump per stuck test process, the held steps never reached, and the event
/// ledger, all side by side where the CI failure upload selects them.
@Suite("Swift lane hang evidence")
struct SwiftLaneHangEvidenceTests {
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

    @Test("a forced hang keeps its task dump and held-step log beside its ledger, where the CI upload finds them")
    func forcedHangKeepsDumpAndHeldStepLogBesideLedger() async throws {
        // The child is a wedged test: it records two held-step waits, only one of
        // which arrives, then stalls. The fake swift-inspect attaches and dumps,
        // as it does for a real test process built with get-task-allow.
        let workDirectory = NSTemporaryDirectory() + "agentstudio-receipt-evidence-\(UUIDv7.generate())"
        defer { try? FileManager.default.removeItem(atPath: workDirectory) }
        let evidenceDirectory = workDirectory + "/ci-runs"
        try FileManager.default.createDirectory(atPath: workDirectory + "/bin", withIntermediateDirectories: true)
        try """
        printf 'waiting\\tgate A\\tSuite.swift first()\\nwaiting\\tgate B\\tSuite.swift second()\\narrived\\tgate A\\n' \
          >> "$AGENTSTUDIO_HELD_STEP_LOG"
        while true; do sleep 1; done

        """.write(toFile: workDirectory + "/wedged-test.sh", atomically: true, encoding: .utf8)
        try """
        #!/bin/bash
        echo TASKS; echo "  Task 1 async backtrace: parkForever()"

        """.write(toFile: workDirectory + "/bin/xcrun", atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: workDirectory + "/bin/xcrun")

        let laneOutput = try await laneBashAllowingFailure(
            "LOG_PREFIX=lane; TIMEOUT_SECONDS=2; BUILD_PATH=.build-agent-1; "
                + "export LANE_EVENT_STREAM_DIR='\(evidenceDirectory)'; export PATH='\(workDirectory)/bin':$PATH; "
                + "source scripts/swift-test-helpers.sh; set +e; "
                + "run_swift_with_timeout 'evidence probe' 2 /bin/bash '\(workDirectory)/wedged-test.sh' "
                + "AgentStudioPackageTests || returned=$?; echo \"RETURNED=${returned:-0}\""
        )
        let evidenceFiles = try FileManager.default.contentsOfDirectory(atPath: evidenceDirectory).sorted()
        let ledger = try #require(evidenceFiles.first { $0.hasSuffix(".events.jsonl") })
        let evidenceStem = String(ledger.dropLast(".events.jsonl".count))
        let taskDumps = evidenceFiles.filter { $0.hasSuffix(".task-dump.txt") }
        let heldStepLog = evidenceStem + ".held-steps.log"
        let uploadGlobs = try ciUploadedEvidenceGlobs()
        let unarrivedRange = try #require(laneOutput.range(of: "lane-report held_step_unarrived "))
        let reapRange = try #require(laneOutput.range(of: "lane-report timeout_reap="))

        // The hang verdict is failed whatever evidence was gathered.
        #expect(laneOutput.contains("RETURNED=124"))
        // Only the wait that never arrived is named, before anything is reaped.
        #expect(laneOutput.contains("lane-report held_step_unarrived name=gate B test=Suite.swift second()"))
        #expect(!laneOutput.contains("held_step_unarrived name=gate A"))
        #expect(unarrivedRange.lowerBound < reapRange.lowerBound)
        // Dump, held-step log and ledger share one stem, side by side.
        #expect(evidenceStem.hasPrefix("lane-evidence-probe-"))
        #expect(!taskDumps.isEmpty)
        #expect(taskDumps.allSatisfy { $0.hasPrefix(evidenceStem + "-pid") })
        #expect(evidenceFiles.contains(heldStepLog))
        #expect(laneOutput.contains("lane-report task_dump=\(evidenceDirectory)/\(evidenceStem)-pid"))
        let firstDump = try String(
            contentsOfFile: evidenceDirectory + "/" + (try #require(taskDumps.first)),
            encoding: .utf8
        )
        #expect(firstDump.contains("parkForever()"))
        // Every file the hang left is one the CI failure upload selects.
        #expect(uploadGlobs.count == 3)
        for evidenceFile in evidenceFiles {
            #expect(
                uploadGlobs.contains { fnmatch($0, evidenceFile, 0) == 0 },
                "\(evidenceFile) is not selected by the CI upload globs \(uploadGlobs)"
            )
        }
    }

    @Test("held-step waits are matched to arrivals in order, and a missing or empty log prints nothing")
    func heldStepWaitsAreMatchedToArrivalsInOrder() async throws {
        let logDirectory = NSTemporaryDirectory() + "agentstudio-receipt-held-\(UUIDv7.generate())"
        defer { try? FileManager.default.removeItem(atPath: logDirectory) }

        let report = try await laneBash(
            "mkdir -p '\(logDirectory)'; "
                // TAB-separated, as the harness writes it: step names contain spaces.
                + "printf 'waiting\\tsocket stop gate\\tListenerTests.swift one()\\n"
                + "waiting\\tsocket stop gate\\tListenerTests.swift two()\\narrived\\tsocket stop gate\\n"
                + "waiting\\tpane focus\\tFocusTests.swift three()\\n' > '\(logDirectory)/held.log'; "
                + ": > '\(logDirectory)/empty.log'; "
                + "LOG_PREFIX=lane; source scripts/swift-test-helpers.sh; "
                + "print_held_steps_unarrived_at_timeout '\(logDirectory)/held.log'; echo MISSING:; "
                + "print_held_steps_unarrived_at_timeout '\(logDirectory)/absent.log'; echo EMPTY:; "
                + "print_held_steps_unarrived_at_timeout '\(logDirectory)/empty.log'; echo UNSET:; "
                + "print_held_steps_unarrived_at_timeout ''"
        )

        #expect(
            laneOutputLines(report) == [
                // One arrival settles the earliest wait of that name.
                "[lane] lane-report held_step_unarrived name=socket stop gate test=ListenerTests.swift two()",
                "[lane] lane-report held_step_unarrived name=pane focus test=FocusTests.swift three()",
                "MISSING:",
                "EMPTY:",
                "UNSET:",
            ]
        )
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
}

/// The file-name globs the CI failure upload selects under the ledger directory.
private func ciUploadedEvidenceGlobs() throws -> [String] {
    let ciWorkflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)
    let uploadStep = try laneScriptNamedBlock(
        startingWith: "      - name: Upload wedged-lane event-stream ledgers",
        endingBefore: "\n      - name: ",
        in: ciWorkflow
    )
    let ledgerDirectoryPrefix = "tmp/plan-workflows/ci-runs/"
    return uploadStep.split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.hasPrefix(ledgerDirectoryPrefix) }
        .map { String($0.dropFirst(ledgerDirectoryPrefix.count)) }
}
