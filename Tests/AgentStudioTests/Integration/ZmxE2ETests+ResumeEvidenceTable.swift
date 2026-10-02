import AgentStudioInfrastructure
import AgentStudioTestHarness
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTerminal

extension E2ESerializedTests.ZmxE2ETests {
    @Test(
        "each agent failure row decides and invokes only its own exact session in real zmx",
        arguments: ResumeEvidenceTableRow.allCases, ["claude-code", "codex"])
    func resumeEvidenceFailureTable(row: ResumeEvidenceTableRow, provider: String) async throws {
        try await withResumeEvidenceBackend { environment in
            let proof = try await ResumeEvidenceZmxProof.make(
                environment: environment, provider: provider,
                historical: row == .startedWhileClosed, unordered: row == .unavailableStore,
                successor: row == .exitIntoAnotherProgram,
                exitWatcher: row == .watchRefused ? ResumeEvidenceFirstRefusalWatch() : nil)
            do {
                if row != .startedWhileClosed && row != .diedBeforeFirstLook {
                    let watchID = try await proof.foreground.initialLook()
                    if row == .watchRefused {
                        let scope = ForegroundObserverFactScope(paneId: proof.data.paneID, operationId: watchID)
                        let retained = try await proof.foreground.repository.load(paneId: proof.data.paneID)
                        try await proof.foreground.facts.expectNext(in: scope, .watchUnavailable(.permissionDenied))
                        try await proof.foreground.facts.expectNext(in: scope, .closed(.looked))
                        #expect(try await proof.foreground.repository.load(paneId: proof.data.paneID) == retained)
                        #expect(await proof.foreground.observer.currentWatch(paneId: proof.data.paneID) == nil)
                        await proof.foreground.clock.waitForPendingSleepCount(atLeast: 1)
                        proof.foreground.clock.advance(by: .seconds(60))
                        let retry = try await proof.foreground.nextLook(sequence: 2)
                        try await proof.foreground.facts.expectNext(in: retry, .observation(.admitted))
                        _ = try await proof.foreground.facts.expectNext(
                            in: retry,
                            where: {
                                if case .watchRegistered = $0 { true } else { false }
                            }, "retry native watch")
                        try await proof.foreground.facts.expectNext(in: retry, .closed(.looked))
                        #expect(try await proof.foreground.repository.load(paneId: proof.data.paneID)?.sequence == 2)
                    }
                }
                switch row {
                case .reportedExit:
                    _ = try await proof.report(
                        event: .sessionEnd(reason: provider == "codex" ? "exit" : "prompt_input_exit"))
                case .missingEndReason:
                    _ = try await proof.report(event: .sessionEnd(reason: nil))
                case .unrecognizedEndReason:
                    _ = try await proof.report(event: .sessionEnd(reason: "future-display-only"))
                case .closedAppRecordedEnd:
                    _ = try await proof.report(event: .sessionEnd(reason: "other"), live: false)
                case .hangupReportedEnd:
                    _ = try await proof.report(event: .sessionEnd(reason: "other"))
                case .exitWithoutEnd, .lostEndAfterFreshLook:
                    try await proof.foreground.letAgentExitIntoShell()
                    let look = try await proof.foreground.nextLook(sequence: 2)
                    try await proof.foreground.facts.expectNext(in: look, .observation(.admitted))
                    try await proof.foreground.facts.expectNext(in: look, .closed(.looked))
                    #expect(try await proof.foreground.repository.load(paneId: proof.data.paneID)?.program == .shell)
                case .exitIntoAnotherProgram:
                    let hold = HeldStep<[ZmxSessionID]>("exit look until successor is foreground")
                    defer { hold.retire() }
                    await proof.foreground.probeGate.holdNext(hold)
                    try await proof.foreground.letAnotherProgramTakeForeground()
                    let look = try await proof.foreground.nextLook(sequence: 2)
                    let requested = try await hold.firstArrival()
                    #expect(requested == [proof.foreground.sessionId])
                    hold.release()
                    try await proof.foreground.facts.expectNext(in: look, .observation(.admitted))
                    try await proof.foreground.facts.expectNext(in: look, .closed(.looked))
                    #expect(try await proof.foreground.repository.load(paneId: proof.data.paneID)?.program == .other)
                case .stoppedAfterLook, .backgroundAfterLook, .closedAppLostEnd, .lostEndBeforeFreshLook:
                    await proof.foreground.observer.shutdown()
                    if row == .stoppedAfterLook || row == .backgroundAfterLook {
                        try await proof.foreground.suspendAgentIntoShell(background: row == .backgroundAfterLook)
                    } else {
                        try await proof.foreground.letAgentExitIntoShell()
                    }
                case .stoppedBeforeLook, .backgroundBeforeLook:
                    try await proof.foreground.suspendAgentIntoShell(background: row == .backgroundBeforeLook)
                    await proof.foreground.observer.note(.relaunched, pane: proof.data.paneID)
                    let look = try await proof.foreground.nextLook(sequence: 2)
                    try await proof.foreground.facts.expectNext(in: look, .observation(.admitted))
                    try await proof.foreground.facts.expectNext(in: look, .closed(.looked))
                    #expect(try await proof.foreground.repository.load(paneId: proof.data.paneID)?.program == .shell)
                default: break
                }
                let observation = try await proof.foreground.observer.takePreRestoreObservation(
                    paneId: proof.data.paneID)
                await proof.foreground.observer.shutdown()
                try await proof.foreground.killOwnedSession()
                try await proof.prepareReadiness()
                let expected = try row.expected(for: proof)
                let verdict = try await proof.decision(
                    observation: observation, reboot: row != .sameBootDeath && row != .hangupReportedEnd)
                try await proof.invoke(verdict, expected: expected, exitCode: row == .targetGone ? 23 : 0)
                try await proof.close()
            } catch {
                try? await proof.close()
                throw error
            }
        }
    }

    @Test(
        "warm launches keep sweep-ended bindings eligible, then resume after actual daemon death",
        arguments: ["claude-code", "codex"])
    func resumeEvidenceRepeatedWarmLaunches(provider: String) async throws {
        try await withResumeEvidenceBackend { environment in
            let proof = try await ResumeEvidenceZmxProof.make(environment: environment, provider: provider)
            do {
                _ = try await proof.foreground.initialLook()
                let fetchedOriginal = try await proof.data.binding()
                let original = try #require(fetchedOriginal)
                await proof.foreground.observer.shutdown()
                for _ in 0..<3 {
                    try await proof.prepareReadiness()
                    let fetchedBinding = try await proof.data.binding()
                    let binding = try #require(fetchedBinding)
                    #expect(binding.bindingGenerationId == original.bindingGenerationId)
                    #expect(binding.providerEndedAt == nil)
                    #expect(binding.status == .ended)
                    #expect(
                        try await proof.foreground.repository.eligiblePanes().map { $0.paneId } == [proof.data.paneID])
                    let look = try await proof.foreground.repository.load(paneId: proof.data.paneID)
                    let verdict = try await proof.decision(observation: look)
                    #expect(verdict == .unknown(.observationMismatch))
                    try await proof.warmAttachWithoutInvocation()
                }
                let look = try await proof.foreground.repository.load(paneId: proof.data.paneID)
                try await proof.foreground.killOwnedSession()
                try await proof.prepareReadiness()
                let decided = try await proof.decision(observation: look)
                try await proof.invoke(decided, expected: proof.candidate())
                try await proof.close()
            } catch {
                try? await proof.close()
                throw error
            }
        }
    }

    @Test(
        "two agent panes in the identical folder invoke their two distinct exact UUIDs",
        arguments: ["claude-code", "codex"])
    func resumeEvidenceTwoPanesOneFolder(provider: String) async throws {
        try await withResumeEvidenceBackend { environment in
            let first = try await ResumeEvidenceZmxProof.make(environment: environment, provider: provider)
            var second: ResumeEvidenceZmxProof?
            do {
                let other = try await ResumeEvidenceZmxProof.make(
                    environment: environment, provider: provider, sharedData: first.data)
                second = other
                #expect(first.sessionID != other.sessionID)
                #expect(first.data.paneID != other.data.paneID)
                #expect(first.data.workspaceID == other.data.workspaceID)
                #expect(first.data.storeID == other.data.storeID)
                #expect(first.data.access.queue === other.data.access.queue)
                for proof in [first, other] {
                    _ = try await proof.foreground.initialLook()
                    let look = try await proof.foreground.observer.takePreRestoreObservation(paneId: proof.data.paneID)
                    await proof.foreground.observer.shutdown()
                    try await proof.foreground.killOwnedSession()
                    try await proof.prepareReadiness()
                    let verdict = try await proof.decision(observation: look, reboot: true)
                    // Both cold plans use harness.zmxDir as the saved folder.
                    try await proof.invoke(verdict, expected: proof.candidate())
                }
                try await other.close()
                second = nil
                try await first.close()
            } catch {
                if let second { try? await second.close() }
                try? await first.close()
                throw error
            }
        }
    }
}

enum ResumeEvidenceTableRow: String, CaseIterable, Sendable {
    case reportedExit, runningAtReboot, exitWithoutEnd, exitIntoAnotherProgram, watchRefused
    case stoppedAfterLook, backgroundAfterLook, closedAppLostEnd, closedAppRecordedEnd, startedWhileClosed
    case lostEndAfterFreshLook, lostEndBeforeFreshLook, diedBeforeFirstLook
    case sameBootDeath, hangupReportedEnd, stoppedBeforeLook, backgroundBeforeLook
    case unavailableStore, targetGone, missingEndReason, unrecognizedEndReason
    func expected(for proof: ResumeEvidenceZmxProof) throws -> ResumeEvidence {
        switch self {
        case .reportedExit: return .knownExited(.personExit)
        case .missingEndReason: return .knownExited(.notGiven)
        case .unrecognizedEndReason: return .knownExited(.unrecognized)
        case .closedAppRecordedEnd, .hangupReportedEnd: return .knownExited(.providerOther)
        case .exitWithoutEnd, .exitIntoAnotherProgram, .lostEndAfterFreshLook,
            .stoppedBeforeLook, .backgroundBeforeLook:
            return .unknown(.programNotAgent)
        case .startedWhileClosed: return .unknown(.startedFromHistoricalReport)
        case .diedBeforeFirstLook: return .unknown(.noObservation)
        case .unavailableStore: return .unknown(.evidenceUnordered)
        default: return try proof.candidate()
        }
    }

}
