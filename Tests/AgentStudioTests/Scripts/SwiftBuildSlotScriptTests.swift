import AgentStudioInfrastructure
import AgentStudioTestHarness
import AgentStudioTestSupport
import Darwin
import Foundation
import Testing

private enum SwiftBuildSlotScriptTestFailure: Error {
    case expectedOperationFailure
}

@Suite("Swift build slot script")
struct SwiftBuildSlotScriptTests {
    @Test("a failed operation closes and reaps its blocked helper")
    func failedOperationClosesAndReapsBlockedHelper() async throws {
        let fixture = try SwiftBuildSlotFixture()

        await #expect(throws: SwiftBuildSlotScriptTestFailure.self) {
            try await fixture.withOwnedProcesses { fixture in
                let helper = fixture.makeProcess("printf 'HELPER_READY\\n'; IFS= read -r _")
                helper.start()
                _ = try await helper.readOutput(until: "HELPER_READY")
                throw SwiftBuildSlotScriptTestFailure.expectedOperationFailure
            }
        }

        let helperPID = try #require(fixture.ownedProcessIdentifiers.first)
        #expect(kill(helperPID, 0) == -1 && errno == ESRCH)
        #expect(!fixture.hasRunningHelpers)
    }

    @Test("cancellation closes and reaps its blocked helper")
    func cancellationClosesAndReapsBlockedHelper() async throws {
        let fixture = try SwiftBuildSlotFixture()
        let helperArrived = HeldStep<Void>("swift-build-slot-helper-blocked-on-stdin")
        let helperTask = Task {
            try await fixture.withOwnedProcesses { fixture in
                let helper = fixture.makeProcess("printf 'HELPER_READY\\n'; IFS= read -r _")
                helper.start()
                _ = try await helper.readOutput(until: "HELPER_READY")
                try await helperArrived.arrive(())
            }
        }

        _ = try await helperArrived.firstArrival()
        helperTask.cancel()
        await #expect(throws: CancellationError.self) {
            try await helperTask.value
        }
        #expect(!fixture.hasRunningHelpers)
    }

    @Test("only named local slots and task labels are accepted")
    func onlyNamedSlotsAndTaskLabelsAreAccepted() async throws {
        let fixture = try SwiftBuildSlotFixture()

        let unknownSlot = try await fixture.run(
            "source scripts/swift-build-slot.sh\nswift_build_slot_acquire compile \"unknown\""
        )
        let missingTask = try await fixture.run(
            "source scripts/swift-build-slot.sh\nswift_build_slot_acquire build"
        )

        #expect(unknownSlot.exitCode != 0)
        #expect(unknownSlot.output.contains("expected slot 'build' or 'test'"))
        #expect(missingTask.exitCode != 0)
        #expect(missingTask.output.contains("task label is required"))
    }

    @Test("build and test own distinct fixed paths without replacing existing contents")
    func buildAndTestSlotsRemainDistinctAndPreserveExistingContents() async throws {
        let fixture = try SwiftBuildSlotFixture()
        let buildMarker = fixture.rootURL.appending(path: ".build-agent-1/build-artifact")
        let testMarker = fixture.rootURL.appending(path: ".build-agent-2/test-artifact")
        try FileManager.default.createDirectory(
            at: buildMarker.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: testMarker.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("existing-build".utf8).write(to: buildMarker)
        try Data("existing-test".utf8).write(to: testMarker)

        let result = try await fixture.withOwnedProcesses { fixture in
            let buildOwner = fixture.makeProcess(
                "source scripts/swift-build-slot.sh\n"
                    + "trap swift_build_slot_release EXIT\n"
                    + "swift_build_slot_acquire build \"build-owner\"\n"
                    + "printf 'BUILD_READY\\n'\n"
                    + "IFS= read -r _ || exit 0\n"
            )
            buildOwner.start()
            var output = try await buildOwner.readOutput(until: "BUILD_READY")

            let testOwner = fixture.makeProcess(
                "source scripts/swift-build-slot.sh\n"
                    + "trap swift_build_slot_release EXIT\n"
                    + "swift_build_slot_acquire test \"test-owner\"\n"
                    + "printf 'TEST_READY\\n'\n"
            )
            testOwner.start()
            output += try await testOwner.readOutputToEnd()
            try writeLine("release\n", to: buildOwner.standardInput)
            output += try await buildOwner.readOutputToEnd()

            return (try await buildOwner.waitForExit(), output)
        }

        #expect(result.0 == 0)
        #expect(result.1.contains("using slot=build path=.build-agent-1 task=build-owner"))
        #expect(result.1.contains("using slot=test path=.build-agent-2 task=test-owner"))
        #expect(try String(contentsOf: buildMarker, encoding: .utf8) == "existing-build")
        #expect(try String(contentsOf: testMarker, encoding: .utf8) == "existing-test")
    }

    @Test("a same-slot claimant reports its holder once and runs after release")
    func secondBuildClaimWaitsWithOneHolderLineAndThenRuns() async throws {
        let fixture = try SwiftBuildSlotFixture()
        let result = try await fixture.withOwnedProcesses { fixture in
            let owner = fixture.makeProcess(
                "source scripts/swift-build-slot.sh\n"
                    + "trap swift_build_slot_release EXIT\n"
                    + "swift_build_slot_acquire build \"build-owner\"\n"
                    + "printf 'OWNER_READY\\n'\n"
                    + "IFS= read -r _ || exit 0\n"
            )
            owner.start()
            _ = try await owner.readOutput(until: "OWNER_READY")

            let waiter = fixture.makeProcess(
                "source scripts/swift-build-slot.sh\n"
                    + "trap swift_build_slot_release EXIT\n"
                    + "swift_build_slot_acquire build \"build-waiter\"\n"
                    + "printf 'WAITER_DONE\\n'\n",
                environment: ["SWIFT_BUILD_SLOT_SLEEP_GATE": "stdin"]
            )
            waiter.start()
            var waiterLog = try await waiter.readOutput(
                until: "waiting slot=build holder_task=build-owner"
            )

            try writeLine("release-owner\n", to: owner.standardInput)
            let ownerStatus = try await owner.waitForExit()
            try writeLine("continue-waiter\n", to: waiter.standardInput)
            waiterLog += try await waiter.readOutput(until: "WAITER_DONE")
            waiterLog += try await waiter.readOutputToEnd()

            return (ownerStatus, try await waiter.waitForExit(), waiterLog)
        }

        let waitingLines = result.2.components(separatedBy: .newlines).filter {
            $0.contains("[swift-build-slot] waiting slot=build")
        }
        #expect(result.0 == 0)
        #expect(result.1 == 0)
        #expect(waitingLines.count == 1)
        #expect(waitingLines.first?.contains("holder_task=build-owner") == true)
        #expect(waitingLines.first?.range(of: #"holder_pid=[0-9]+"#, options: .regularExpression) != nil)
        #expect(waitingLines.first?.contains("holder_start=Mon Sep 1 00:00:00 2025") == true)
        #expect(!result.2.contains("reaped stale"))
    }

    @Test("dead and reused PID claims are reaped before a new owner is admitted")
    func deadAndReusedPIDClaimsAreReaped() async throws {
        let deadFixture = try SwiftBuildSlotFixture()
        try deadFixture.createClaim(
            slotDirectory: ".build-agent-1",
            processID: "987654321",
            startTime: "Mon Sep 1 00:00:00 2025",
            task: "dead-holder"
        )
        let deadResult = try await deadFixture.run(
            "source scripts/swift-build-slot.sh\n"
                + "trap swift_build_slot_release EXIT\n"
                + "swift_build_slot_acquire build \"replacement-owner\""
        )

        let reusedFixture = try SwiftBuildSlotFixture()
        let reusedResult = try await reusedFixture.run(
            "export SWIFT_BUILD_SLOT_PS_REUSED_PID=\"$$\"\n"
                + "export SWIFT_BUILD_SLOT_PS_REUSED_START=\"Tue Sep 2 00:00:00 2025\"\n"
                + "mkdir -p .build-agent-1/.slot-claim\n"
                + "printf '%s\\t%s\\t%s\\n' \"$$\" \"Mon Sep 1 00:00:00 2025\" \"reused-holder\" > .build-agent-1/.slot-claim/holder\n"
                + "source scripts/swift-build-slot.sh\n"
                + "trap swift_build_slot_release EXIT\n"
                + "swift_build_slot_acquire build \"replacement-owner\""
        )

        #expect(deadResult.exitCode == 0)
        #expect(deadResult.output.contains("reaped stale slot=build task=dead-holder"))
        #expect(deadResult.output.contains("using slot=build path=.build-agent-1 task=replacement-owner"))
        #expect(reusedResult.exitCode == 0)
        #expect(reusedResult.output.contains("reaped stale slot=build task=reused-holder"))
        #expect(reusedResult.output.contains("using slot=build path=.build-agent-1 task=replacement-owner"))
    }

    @Test("a later claimant reaps an orphaned stale reaper lock")
    func laterClaimantReapsOrphanedStaleReaperLock() async throws {
        let fixture = try SwiftBuildSlotFixture()
        try fixture.createClaim(
            slotDirectory: ".build-agent-1",
            processID: "987654321",
            startTime: "Mon Sep 1 00:00:00 2025",
            task: "abandoned-holder"
        )
        let reaperDirectory = fixture.rootURL.appending(path: ".build-agent-1/.slot-claim/.reaper-lock")
        try FileManager.default.createDirectory(at: reaperDirectory, withIntermediateDirectories: true)
        try Data("987654321\tMon Sep 1 00:00:00 2025\n".utf8)
            .write(to: reaperDirectory.appending(path: "holder"))

        let result = try await fixture.run(
            "source scripts/swift-build-slot.sh\n"
                + "trap swift_build_slot_release EXIT\n"
                + "swift_build_slot_acquire build \"replacement-owner\""
        )

        #expect(result.exitCode == 0)
        #expect(result.output.contains("reaped stale reaper lock pid=987654321"))
        #expect(result.output.contains("reaped stale slot=build task=abandoned-holder"))
        #expect(result.output.contains("using slot=build path=.build-agent-1 task=replacement-owner"))
        #expect(!FileManager.default.fileExists(atPath: reaperDirectory.path))
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.rootURL.appending(path: ".build-agent-1/.slot-claim").path
            )
        )
    }

    @Test("a live descendant with an open build file prevents stale claim cleanup")
    func liveDescendantOpenFilePreventsStaleClaimCleanup() async throws {
        let fixture = try SwiftBuildSlotFixture()
        let buildFile = fixture.rootURL.appending(path: ".build-agent-1/descendant.open")
        try FileManager.default.createDirectory(
            at: buildFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("open".utf8).write(to: buildFile)
        try FileManager.default.createDirectory(at: fixture.openFilesMarkerURL, withIntermediateDirectories: true)
        try Data("open".utf8).write(to: fixture.openFilesMarkerURL.appending(path: ".build-agent-1"))

        let result = try await fixture.withOwnedProcesses { fixture in
            let owner = fixture.makeProcess(
                "source scripts/swift-build-slot.sh\n"
                    + "trap swift_build_slot_release EXIT\n"
                    + "swift_build_slot_acquire build \"abandoned-owner\"\n"
                    + "/bin/bash -c 'exec 3< \"$SWIFT_BUILD_DIR/descendant.open\"; printf \"DESCENDANT_READY\\n\"; IFS= read -r _; exec 3<&-; printf \"DESCENDANT_DONE\\n\"' <&0 &\n"
                    + "printf 'DESCENDANT_PID=%s\\n' \"$!\"\n"
                    + "printf 'OWNER_READY\\n'\n"
                    + "IFS= read -r _ || exit 0\n"
            )
            owner.start()
            var ownerLog = try await owner.readOutput(until: "DESCENDANT_READY")
            guard
                let descendantPID =
                    ownerLog
                    .components(separatedBy: .newlines)
                    .first(where: { $0.hasPrefix("DESCENDANT_PID=") })?
                    .split(separator: "=").last
                    .flatMap({ Int32($0) })
            else {
                throw SwiftBuildSlotScriptError.missingDescendantPID(ownerLog)
            }

            _ = kill(Int32(owner.processIdentifier), SIGKILL)

            let waiter = fixture.makeProcess(
                "source scripts/swift-build-slot.sh\n"
                    + "trap swift_build_slot_release EXIT\n"
                    + "swift_build_slot_acquire build \"replacement-owner\"\n"
                    + "printf 'CLAIM_DONE\\n'\n",
                environment: ["SWIFT_BUILD_SLOT_SLEEP_GATE": "stdin"]
            )
            waiter.start()
            var waiterLog = try await waiter.readOutput(until: "stale_pid_open_files=true")
            let claimStillExists = FileManager.default.fileExists(
                atPath: fixture.rootURL.appending(path: ".build-agent-1/.slot-claim").path
            )
            let descendantIsAlive = kill(descendantPID, 0) == 0

            try writeLine("release-descendant\n", to: owner.standardInput)
            ownerLog += try await owner.readOutput(until: "DESCENDANT_DONE")
            _ = try await owner.readOutputToEnd()
            try FileManager.default.removeItem(at: fixture.openFilesMarkerURL.appending(path: ".build-agent-1"))
            try writeLine("continue-reaper\n", to: waiter.standardInput)
            waiterLog += try await waiter.readOutput(until: "CLAIM_DONE")
            waiterLog += try await waiter.readOutputToEnd()

            _ = try await owner.waitForExit()
            return (
                try await waiter.waitForExit(),
                claimStillExists,
                descendantIsAlive,
                waiterLog
            )
        }

        #expect(result.0 == 0)
        #expect(result.1)
        #expect(result.2)
        #expect(result.3.contains("reaped stale slot=build task=abandoned-owner"))
        #expect(result.3.contains("using slot=build path=.build-agent-1 task=replacement-owner"))
    }

    @Test("normal and nonzero exits both release a named slot")
    func normalAndNonzeroExitsReleaseClaim() async throws {
        let fixture = try SwiftBuildSlotFixture()

        for exitCode in [0, 23] {
            let result = try await fixture.run(
                "source scripts/swift-build-slot.sh\n"
                    + "trap swift_build_slot_release EXIT\n"
                    + "swift_build_slot_acquire test \"exit-$exitCode\"\n"
                    + "exit $exitCode"
                    .replacingOccurrences(of: "$exitCode", with: String(exitCode))
            )
            #expect(result.exitCode == exitCode)
            #expect(
                !FileManager.default.fileExists(
                    atPath: fixture.rootURL.appending(path: ".build-agent-2/.slot-claim").path
                )
            )
        }
    }

    @Test("a handled termination signal releases its named slot")
    func handledSignalReleasesClaim() async throws {
        let fixture = try SwiftBuildSlotFixture()
        let result = try await fixture.withOwnedProcesses { fixture in
            let process = fixture.makeProcess(
                "source scripts/swift-build-slot.sh\n"
                    + "trap swift_build_slot_release EXIT\n"
                    + "trap 'exit 143' TERM\n"
                    + "swift_build_slot_acquire test \"signal-owner\"\n"
                    + "/bin/bash -c 'sleep 1' <&0 &\n"
                    + "sleep_child_pid=$!\n"
                    + "printf 'SIGNAL_READY\\n'\n"
                    + "wait \"$sleep_child_pid\"\n",
                environment: ["SWIFT_BUILD_SLOT_SLEEP_GATE": "stdin"]
            )
            process.start()
            let log = try await process.readOutput(until: "SIGNAL_READY")
            _ = kill(Int32(process.processIdentifier), SIGTERM)
            try writeLine("finish-sleep-child\n", to: process.standardInput)
            let outputTail = try await process.readOutputToEnd()
            return (try await process.waitForExit(), log + outputTail)
        }

        #expect(result.0 == 143)
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.rootURL.appending(path: ".build-agent-2/.slot-claim").path
            )
        )
    }

    @Test("CI bypass is exact and local build directory overrides stay rejected")
    func ciBypassAndLocalOverrideContract() async throws {
        let fixture = try SwiftBuildSlotFixture()

        for environment in [
            ["CI": "true", "SWIFT_BUILD_DIR": ".build-ci"],
            ["GITHUB_ACTIONS": "true", "SWIFT_BUILD_DIR": ".build-ci"],
        ] {
            let result = try await fixture.run(
                "source scripts/swift-build-slot.sh\nswift_build_slot_acquire build \"ci-task\"",
                environment: environment
            )
            #expect(result.exitCode == 0)
            #expect(result.output.contains("using CI build path .build-ci"))
        }

        let localOverride = try await fixture.run(
            "source scripts/swift-build-slot.sh\nswift_build_slot_acquire build \"local-task\"",
            environment: ["SWIFT_BUILD_DIR": ".build-local"]
        )
        #expect(localOverride.exitCode != 0)
        #expect(localOverride.output.contains("local SWIFT_BUILD_DIR overrides are not supported"))
        #expect(!FileManager.default.fileExists(atPath: fixture.rootURL.appending(path: ".build-agent-1").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.rootURL.appending(path: ".build-agent-2").path))
    }

    @Test("the test runner receipt handler releases the slot and preserves failure status")
    func runnerExitHandlerEmitsReceiptAndReleasesAfterFailure() async throws {
        let fixture = try SwiftBuildSlotFixture()
        let runnerSource = try String(contentsOfFile: "scripts/run-swift-test-task.sh", encoding: .utf8)
        let exitHandler = try swiftBuildSlotShellFunction(named: "finish_lane_invocation", in: runnerSource)
        let result = try await fixture.run(
            "source scripts/swift-build-slot.sh\n"
                + "swift_build_slot_acquire test \"runner-failure\"\n"
                + "print_closing_lane_report() { printf 'lane-receipt exit_status=%s\\n' \"$1\"; }\n"
                + exitHandler + "\n"
                + "trap finish_lane_invocation EXIT\n"
                + "exit 17"
        )

        #expect(result.exitCode == 17)
        #expect(result.output.contains("lane-receipt exit_status=17"))
        #expect(result.output.contains("released slot=test task=runner-failure"))
        #expect(result.output.components(separatedBy: "released slot=test task=runner-failure").count == 2)
        #expect(!runnerSource.contains("LANE_SLOT_RELEASE_COMMAND"))
        #expect(!runnerSource.contains("trap -p EXIT"))
        #expect(
            !FileManager.default.fileExists(atPath: fixture.rootURL.appending(path: ".build-agent-2/.slot-claim").path))
    }

    @Test("cleanup removes only an idle empty legacy claim")
    func cleanupReapsOnlyIdleLegacyClaim() async throws {
        let fixture = try SwiftBuildSlotFixture()
        let idleClaim = fixture.rootURL.appending(path: ".build-agent-1/.slot-claim")
        let activeClaim = fixture.rootURL.appending(path: ".build-agent-2/.slot-claim")
        try FileManager.default.createDirectory(at: idleClaim, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: activeClaim, withIntermediateDirectories: true)
        try Data().write(to: idleClaim.appending(path: "holder"))
        try FileManager.default.createDirectory(at: fixture.openFilesMarkerURL, withIntermediateDirectories: true)
        try Data("open".utf8).write(to: fixture.openFilesMarkerURL.appending(path: ".build-agent-2"))

        let miseConfig = try String(contentsOfFile: ".mise.toml", encoding: .utf8)
        let cleanerBody = try miseTaskBody(named: "clean-agent-builds", in: miseConfig)
        let result = try await fixture.run(
            cleanerBody,
            environment: ["PROJECT_ROOT": fixture.rootURL.path]
        )

        #expect(result.exitCode == 0)
        #expect(!FileManager.default.fileExists(atPath: idleClaim.path))
        #expect(FileManager.default.fileExists(atPath: activeClaim.path))
        #expect(result.output.contains("legacy"))
        #expect(result.output.contains("holder_pid=4242"))
        #expect(result.output.contains("holder_start=Mon Sep 1 00:00:00 2025"))
    }
}
