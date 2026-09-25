import AgentStudioInfrastructure
import AgentStudioTestSupport
import Darwin
import Foundation
import Testing

@Suite("Swift build slot script")
struct SwiftBuildSlotScriptTests {
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

        let releaseFIFO = fixture.rootURL.appending(path: "release-build.fifo")
        try fixture.createFIFO(at: releaseFIFO)
        let result = try await withoutBlockingCooperativePool {
            let buildOwner = fixture.makeProcess(
                "source scripts/swift-build-slot.sh\n"
                    + "trap swift_build_slot_release EXIT\n"
                    + "swift_build_slot_acquire build \"build-owner\"\n"
                    + "printf 'BUILD_READY\\n'\n"
                    + "IFS= read -r _ < \"$BUILD_RELEASE_FIFO\"\n",
                environment: ["BUILD_RELEASE_FIFO": releaseFIFO.path]
            )
            let buildOutput = Pipe()
            buildOwner.standardOutput = buildOutput
            buildOwner.standardError = buildOutput
            try buildOwner.run()
            var buildLog = ""
            try readOutput(buildOutput.fileHandleForReading, into: &buildLog, until: "BUILD_READY")

            let testOwner = fixture.makeProcess(
                "source scripts/swift-build-slot.sh\n"
                    + "trap swift_build_slot_release EXIT\n"
                    + "swift_build_slot_acquire test \"test-owner\"\n"
                    + "printf 'TEST_READY\\n'\n"
            )
            let testOutput = Pipe()
            testOwner.standardOutput = testOutput
            testOwner.standardError = testOutput
            try testOwner.run()
            let testLog = try readOutputToEnd(testOutput.fileHandleForReading)
            testOwner.waitUntilExit()

            try writeLine("release\n", to: releaseFIFO)
            buildOwner.waitUntilExit()
            return (buildOwner.terminationStatus, buildLog + testLog)
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
        let ownerReleaseFIFO = fixture.rootURL.appending(path: "owner-release.fifo")
        let sleepGateFIFO = fixture.rootURL.appending(path: "sleep-gate.fifo")
        try fixture.createFIFO(at: ownerReleaseFIFO)
        try fixture.createFIFO(at: sleepGateFIFO)

        let result = try await withoutBlockingCooperativePool {
            let owner = fixture.makeProcess(
                "source scripts/swift-build-slot.sh\n"
                    + "trap swift_build_slot_release EXIT\n"
                    + "swift_build_slot_acquire build \"build-owner\"\n"
                    + "printf 'OWNER_READY\\n'\n"
                    + "IFS= read -r _ < \"$OWNER_RELEASE_FIFO\"\n",
                environment: ["OWNER_RELEASE_FIFO": ownerReleaseFIFO.path]
            )
            let ownerOutput = Pipe()
            owner.standardOutput = ownerOutput
            owner.standardError = ownerOutput
            try owner.run()
            var ownerLog = ""
            try readOutput(ownerOutput.fileHandleForReading, into: &ownerLog, until: "OWNER_READY")

            let waiter = fixture.makeProcess(
                "source scripts/swift-build-slot.sh\n"
                    + "trap swift_build_slot_release EXIT\n"
                    + "swift_build_slot_acquire build \"build-waiter\"\n"
                    + "printf 'WAITER_DONE\\n'\n",
                environment: ["SWIFT_BUILD_SLOT_SLEEP_GATE": sleepGateFIFO.path]
            )
            let waiterOutput = Pipe()
            waiter.standardOutput = waiterOutput
            waiter.standardError = waiterOutput
            try waiter.run()
            var waiterLog = ""
            try readOutput(
                waiterOutput.fileHandleForReading,
                into: &waiterLog,
                until: "waiting slot=build holder_task=build-owner"
            )

            try writeLine("release-owner\n", to: ownerReleaseFIFO)
            owner.waitUntilExit()
            try writeLine("continue-waiter\n", to: sleepGateFIFO)
            try readOutput(waiterOutput.fileHandleForReading, into: &waiterLog, until: "WAITER_DONE")
            waiter.waitUntilExit()
            return (owner.terminationStatus, waiter.terminationStatus, ownerLog, waiterLog)
        }

        let waitingLines = result.3.components(separatedBy: .newlines).filter {
            $0.contains("[swift-build-slot] waiting slot=build")
        }
        #expect(result.0 == 0)
        #expect(result.1 == 0)
        #expect(waitingLines.count == 1)
        #expect(waitingLines.first?.contains("holder_task=build-owner") == true)
        #expect(waitingLines.first?.range(of: #"holder_pid=[0-9]+"#, options: .regularExpression) != nil)
        #expect(waitingLines.first?.contains("holder_start=Mon Sep 1 00:00:00 2025") == true)
        #expect(!result.3.contains("reaped stale"))
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
        let ownerReleaseFIFO = fixture.rootURL.appending(path: "owner-release.fifo")
        let descendantReleaseFIFO = fixture.rootURL.appending(path: "descendant-release.fifo")
        let sleepGateFIFO = fixture.rootURL.appending(path: "sleep-gate.fifo")
        let buildFile = fixture.rootURL.appending(path: ".build-agent-1/descendant.open")
        try FileManager.default.createDirectory(
            at: buildFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("open".utf8).write(to: buildFile)
        try fixture.createFIFO(at: ownerReleaseFIFO)
        try fixture.createFIFO(at: descendantReleaseFIFO)
        try fixture.createFIFO(at: sleepGateFIFO)
        try FileManager.default.createDirectory(at: fixture.openFilesMarkerURL, withIntermediateDirectories: true)
        try Data("open".utf8).write(to: fixture.openFilesMarkerURL.appending(path: ".build-agent-1"))

        let result = try await withoutBlockingCooperativePool {
            let owner = fixture.makeProcess(
                "source scripts/swift-build-slot.sh\n"
                    + "trap swift_build_slot_release EXIT\n"
                    + "swift_build_slot_acquire build \"abandoned-owner\"\n"
                    + "/bin/bash -c 'exec 3< \"$SWIFT_BUILD_DIR/descendant.open\"; printf \"DESCENDANT_READY\\n\"; IFS= read -r _ < \"$DESCENDANT_RELEASE_FIFO\"; exec 3<&-; printf \"DESCENDANT_DONE\\n\"' &\n"
                    + "printf 'DESCENDANT_PID=%s\\n' \"$!\"\n"
                    + "printf 'OWNER_READY\\n'\n"
                    + "IFS= read -r _ < \"$OWNER_RELEASE_FIFO\"\n",
                environment: [
                    "OWNER_RELEASE_FIFO": ownerReleaseFIFO.path,
                    "DESCENDANT_RELEASE_FIFO": descendantReleaseFIFO.path,
                ]
            )
            let ownerOutput = Pipe()
            owner.standardOutput = ownerOutput
            owner.standardError = ownerOutput
            try owner.run()
            var ownerLog = ""
            try readOutput(ownerOutput.fileHandleForReading, into: &ownerLog, until: "DESCENDANT_READY")
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
            owner.waitUntilExit()

            let waiter = fixture.makeProcess(
                "source scripts/swift-build-slot.sh\n"
                    + "trap swift_build_slot_release EXIT\n"
                    + "swift_build_slot_acquire build \"replacement-owner\"\n"
                    + "printf 'CLAIM_DONE\\n'\n",
                environment: ["SWIFT_BUILD_SLOT_SLEEP_GATE": sleepGateFIFO.path]
            )
            let waiterOutput = Pipe()
            waiter.standardOutput = waiterOutput
            waiter.standardError = waiterOutput
            try waiter.run()
            var waiterLog = ""
            try readOutput(
                waiterOutput.fileHandleForReading,
                into: &waiterLog,
                until: "stale_pid_open_files=true"
            )
            let claimStillExists = FileManager.default.fileExists(
                atPath: fixture.rootURL.appending(path: ".build-agent-1/.slot-claim").path
            )
            let descendantIsAlive = kill(descendantPID, 0) == 0

            try writeLine("release-descendant\n", to: descendantReleaseFIFO)
            try readOutput(ownerOutput.fileHandleForReading, into: &ownerLog, until: "DESCENDANT_DONE")
            try FileManager.default.removeItem(at: fixture.openFilesMarkerURL.appending(path: ".build-agent-1"))
            try writeLine("continue-reaper\n", to: sleepGateFIFO)
            try readOutput(waiterOutput.fileHandleForReading, into: &waiterLog, until: "CLAIM_DONE")
            waiter.waitUntilExit()
            return (waiter.terminationStatus, claimStillExists, descendantIsAlive, waiterLog)
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
        let sleepGateFIFO = fixture.rootURL.appending(path: "signal-sleep-gate.fifo")
        try fixture.createFIFO(at: sleepGateFIFO)
        let result = try await withoutBlockingCooperativePool {
            let process = fixture.makeProcess(
                "source scripts/swift-build-slot.sh\n"
                    + "trap swift_build_slot_release EXIT\n"
                    + "trap 'exit 143' TERM\n"
                    + "swift_build_slot_acquire test \"signal-owner\"\n"
                    + "/bin/bash -c 'sleep 1' &\n"
                    + "sleep_child_pid=$!\n"
                    + "printf 'SIGNAL_READY\\n'\n"
                    + "wait \"$sleep_child_pid\"\n",
                environment: ["SWIFT_BUILD_SLOT_SLEEP_GATE": sleepGateFIFO.path]
            )
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            var log = ""
            try readOutput(output.fileHandleForReading, into: &log, until: "SIGNAL_READY")
            _ = kill(Int32(process.processIdentifier), SIGTERM)
            try writeLine("finish-sleep-child\n", to: sleepGateFIFO)
            process.waitUntilExit()
            return (process.terminationStatus, log + (try readOutputToEnd(output.fileHandleForReading)))
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
