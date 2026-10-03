import AgentStudioInfrastructure
import AgentStudioSessions
import AgentStudioTestHarness
import AgentStudioTestSupport
import Foundation
import GRDB
import Testing

@testable import AgentStudio
@testable import AgentStudioCLIStore
@testable import AgentStudioCore

extension CLILifecycleReportIntakeTests {
    @Test(
        "a refused end advances the cursor but durably blocks stale-positive resume and never blocks later safe reports",
        arguments: [false, true])
    func refusedEndPoisonsResumeAcrossReopen(undecodable: Bool) async throws {
        try await withLifecycleIntakeFixture { fixture in
            let intake = fixture.intake()
            _ = try await intake.captureListenerReadyBoundary()
            let earlier = try await fixture.seed(fixture.record())
            let earlierAdmission = try await intake.recordLive(
                paneId: fixture.paneID, params: fixture.params(earlier.record, sequence: earlier.sequence))
            #expect(earlierAdmission.disposition == .admitted)
            let current = try await fixture.seed(fixture.record())
            let currentAdmission = try await intake.recordLive(
                paneId: fixture.paneID, params: fixture.params(current.record, sequence: current.sequence))
            #expect(currentAdmission.disposition == .admitted)
            let other = fixture.sharingStore(for: UUIDv7.generate())
            let otherStart = try await other.seed(other.record())
            let otherAdmission = try await intake.recordLive(
                paneId: other.paneID, params: other.params(otherStart.record, sequence: otherStart.sequence))
            #expect(otherAdmission.disposition == .admitted)
            let look = try await persistLifecycleSafetyLook(fixture)
            let otherLook = try await persistLifecycleSafetyLook(other)
            let before = try await storedLifecycleSafetyVerdict(fixture, sessionID: look.zmxSessionId)
            let currentInvocation = ResumeInvocation(
                provider: .codex, sessionId: try ProviderSessionId(rawValue: current.record.conversationID))
            #expect(before == .interruptedCandidate(currentInvocation))

            let end = try await seedRefusedLifecycleEnd(
                fixture, sessionID: current.record.conversationID, undecodable: undecodable)
            try await intake.takeIn(through: .stored(storeId: fixture.storeID, sequence: end.sequence))
            let refusedState = try await fixture.state()
            let refusedBinding = try await fixture.binding()
            #expect(refusedState.mark == end.sequence)
            #expect(refusedBinding?.providerEndedAt == nil)
            #expect(refusedBinding?.bindingGenerationId == look.bindingGenerationId)
            #expect(refusedBinding?.evidenceUnordered == true)
            let refusedVerdict = try await storedLifecycleSafetyVerdict(fixture, sessionID: look.zmxSessionId)
            #expect(refusedVerdict == .unknown(.evidenceUnordered))
            let otherBinding = try await other.binding()
            #expect(otherBinding?.evidenceUnordered == undecodable)
            #expect(fixture.refusals.snapshot().last == (undecodable ? .invalidStoredRow : .qualificationRejected))
            try await closeLifecycleSafetyFiles(fixture)

            let reopened = try await reopenLifecycleSafetyFiles(fixture)
            do {
                let reopenedOther = reopened.sharingStore(for: other.paneID)
                let reopenedVerdict = try await storedLifecycleSafetyVerdict(reopened, sessionID: look.zmxSessionId)
                #expect(reopenedVerdict == .unknown(.evidenceUnordered))
                let otherVerdict = try await storedLifecycleSafetyVerdict(
                    reopenedOther, sessionID: otherLook.zmxSessionId)
                if undecodable {
                    #expect(otherVerdict == .unknown(.evidenceUnordered))
                } else {
                    let otherInvocation = ResumeInvocation(
                        provider: .codex, sessionId: try ProviderSessionId(rawValue: otherStart.record.conversationID))
                    #expect(otherVerdict == .interruptedCandidate(otherInvocation))
                }
                let reopenedIntake = reopened.intake()
                // Establish the existing recovery fence before a later safe row is appended.
                let boundary = try await reopenedIntake.captureListenerReadyBoundary()
                try await reopenedIntake.takeIn(through: boundary)
                let lateOldEnd = try await reopened.seed(
                    reopened.record(
                        sessionID: earlier.record.conversationID, event: .sessionEnd(reason: "exit")))
                let lateAdmission = try await reopenedIntake.recordLive(
                    paneId: reopened.paneID,
                    params: reopened.params(lateOldEnd.record, sequence: lateOldEnd.sequence))
                #expect(lateAdmission.disposition == .admitted)
                let afterOldEnd = try await reopened.binding()
                #expect(afterOldEnd?.bindingGenerationId == look.bindingGenerationId)
                #expect(afterOldEnd?.evidenceUnordered == true)
                let afterOldVerdict = try await storedLifecycleSafetyVerdict(reopened, sessionID: look.zmxSessionId)
                #expect(afterOldVerdict == .unknown(.evidenceUnordered))
                let afterOldState = try await reopened.state()
                #expect(afterOldState.mark == lateOldEnd.sequence)
                let oldEndWasApplied = try await reopened.access.read { database in
                    try String.fetchOne(
                        database,
                        sql: """
                            SELECT binding.provider_ended_at FROM sessions_pane_binding binding
                            JOIN sessions_conversation conversation ON conversation.id=binding.conversation_id
                            WHERE binding.pane_id=? AND conversation.provider_conversation_id=?
                            """, arguments: [reopened.paneID.uuidString, earlier.record.conversationID])
                }
                #expect(oldEndWasApplied != nil)
                let safeCurrentEnd = try await reopened.seed(
                    reopened.record(
                        sessionID: current.record.conversationID, event: .sessionEnd(reason: "exit")))
                let safeAdmission = try await reopenedIntake.recordLive(
                    paneId: reopened.paneID,
                    params: reopened.params(safeCurrentEnd.record, sequence: safeCurrentEnd.sequence))
                #expect(safeAdmission.disposition == .admitted)
                let recoveredBinding = try await reopened.binding()
                #expect(recoveredBinding?.evidenceUnordered == false)
                let recoveredVerdict = try await storedLifecycleSafetyVerdict(reopened, sessionID: look.zmxSessionId)
                #expect(recoveredVerdict == .knownExited(.personExit))
                let recoveredState = try await reopened.state()
                #expect(recoveredState.mark == safeCurrentEnd.sequence)
                try await closeLifecycleSafetyFiles(reopened)
            } catch {
                try? await closeLifecycleSafetyFiles(reopened)
                throw error
            }
        }
    }
}

private func seedRefusedLifecycleEnd(
    _ fixture: LifecycleIntakeFileFixture, sessionID: String, undecodable: Bool
) async throws -> CLILifecycleReport {
    let end = try await fixture.seed(
        fixture.record(
            sessionID: sessionID, event: .sessionEnd(reason: "exit"),
            version: undecodable ? nil : "future-version"))
    if undecodable {
        try await valueFromDedicatedThread {
            let writer = try CLIStore.openWriter(url: fixture.storeURL, channel: .debug).get()
            try writer.databaseQueue.write { database in
                try database.execute(
                    sql: "UPDATE cli_lifecycle_report SET pane_id='not-a-pane-uuid' WHERE sequence=?",
                    arguments: [end.sequence])
            }
            try writer.databaseQueue.close()
        }
    }
    return end
}
