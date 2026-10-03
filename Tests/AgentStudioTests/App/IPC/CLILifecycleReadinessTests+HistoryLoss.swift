import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import AgentStudioTestHarness
import AgentStudioTestSupport
import Foundation
import GRDB
import Testing

@testable import AgentStudio
@testable import AgentStudioCLIStore
@testable import AgentStudioCore

extension CLILifecycleReadinessTests {
    @Test(
        "missing or replaced established CLI history cannot resume from a retained positive look, and safe new history recovers",
        arguments: [false, true])
    func lostEstablishedHistoryPoisonsColdResume(replace: Bool) async throws {
        try await withLifecycleIntakeFixture { fixture in
            let intake = fixture.intake()
            _ = try await intake.captureListenerReadyBoundary()
            let start = try await fixture.seed(fixture.record())
            let admission = try await intake.recordLive(
                paneId: fixture.paneID, params: fixture.params(start.record, sequence: start.sequence))
            #expect(admission.disposition == .admitted)
            let look = try await persistLifecycleSafetyLook(fixture)
            let before = try await storedLifecycleSafetyVerdict(fixture, sessionID: look.zmxSessionId)
            let invocation = ResumeInvocation(
                provider: .codex, sessionId: try ProviderSessionId(rawValue: start.record.conversationID))
            #expect(before == .interruptedCandidate(invocation))
            let end = try await fixture.seed(
                fixture.record(
                    sessionID: start.record.conversationID, event: .sessionEnd(reason: "exit")))
            let established = try await fixture.state()
            #expect(established.mark == start.sequence)
            #expect(end.sequence > established.mark)
            let unread = try await valueFromDedicatedThread {
                let reader = try CLIStore.openReader(url: fixture.storeURL, expectedChannel: .debug).get()
                let batch = try reader.readLifecycleReports(after: established.mark).get()
                try reader.databaseQueue.close()
                return batch
            }
            #expect(unread.reports.map { $0.sequence } == [end.sequence])
            try await closeLifecycleSafetyFiles(fixture)
            let replacementID = try await removeLifecycleSafetyStore(fixture, replace: replace)
            if replace { #expect(replacementID != fixture.storeID) }

            let reopened = try await reopenLifecycleSafetyFiles(fixture)
            do {
                let oldCursor = try await reopened.access.read { database in
                    try Int64.fetchOne(
                        database, sql: "SELECT last_handled_sequence FROM sessions_cli_report_cursor WHERE store_id=?",
                        arguments: [fixture.storeID.uuidString])
                }
                #expect(oldCursor == start.sequence)
                let decided = try await productionLifecycleSafetyColdPlan(reopened, look: look)
                #expect(decided.plan.resume == nil)
                let retainedBinding = try await reopened.binding()
                #expect(retainedBinding?.bindingGenerationId == look.bindingGenerationId)
                #expect(retainedBinding?.providerEndedAt == nil)
                #expect(retainedBinding?.evidenceUnordered == true)
                let verdict = try await storedLifecycleSafetyVerdict(reopened, sessionID: look.zmxSessionId)
                #expect(verdict == .unknown(.evidenceUnordered))
                let fileExists = FileManager.default.fileExists(atPath: reopened.storeURL.path)
                #expect(fileExists == replace, "App readiness/resolution must not create the missing CLI store")

                // An external CLI owner establishes a new store; App only reads and fences it.
                let activeID = try await valueFromDedicatedThread {
                    let writer = try CLIStore.openWriter(url: reopened.storeURL, channel: .debug).get()
                    let storeID = writer.identity.storeID
                    try writer.databaseQueue.close()
                    return storeID
                }
                let recoveryIntake = reopened.intake()
                _ = try await recoveryIntake.captureListenerReadyBoundary()
                let recoveryRecord = reopened.record()
                let recovery = try await reopened.seed(recoveryRecord)
                let recovered = try await recoveryIntake.recordLive(
                    paneId: reopened.paneID,
                    params: reopened.params(recovery.record, sequence: recovery.sequence, storeID: activeID))
                #expect(recovered.disposition == .admitted)
                let recoveredBinding = try await reopened.binding()
                #expect(recoveredBinding?.providerConversationId == recoveryRecord.conversationID)
                #expect(recoveredBinding?.evidenceUnordered == false)
                let recoveryMark = try await reopened.access.read { database in
                    try Int64.fetchOne(
                        database, sql: "SELECT last_handled_sequence FROM sessions_cli_report_cursor WHERE store_id=?",
                        arguments: [activeID.uuidString])
                }
                #expect(recoveryMark == recovery.sequence)
                let recoveryLook = try await persistLifecycleSafetyLook(reopened)
                let recoveryVerdict = try await storedLifecycleSafetyVerdict(
                    reopened, sessionID: recoveryLook.zmxSessionId)
                let expectedRecovery = ResumeInvocation(
                    provider: .codex, sessionId: try ProviderSessionId(rawValue: recoveryRecord.conversationID))
                #expect(recoveryVerdict == .interruptedCandidate(expectedRecovery))
                try await closeLifecycleSafetyFiles(reopened)
            } catch {
                try? await closeLifecycleSafetyFiles(reopened)
                throw error
            }
        }
    }

    @Test("first use with no durable CLI cursor keeps the empty-store readiness path")
    func firstUseWithoutHistoryRemainsReady() async throws {
        try await withLifecycleIntakeFixture { fixture in
            // A qualified binding predating this CLI-store protocol has no store receipt/cursor.
            let record = fixture.record()
            let admitted = try await fixture.adapter().recordProviderEvent(
                paneId: fixture.paneID, params: fixture.params(record), provenance: .matchingPane)
            #expect(admitted.disposition == .admitted)
            let look = try await persistLifecycleSafetyLook(fixture)
            let cursorRows = try await fixture.access.read { database in
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM sessions_cli_report_cursor")
            }
            #expect(cursorRows == 0)
            try await closeLifecycleSafetyFiles(fixture)
            _ = try await removeLifecycleSafetyStore(fixture, replace: false)
            let reopened = try await reopenLifecycleSafetyFiles(fixture)
            do {
                let decided = try await productionLifecycleSafetyColdPlan(reopened, look: look)
                #expect(decided.readiness == .ready)
                let expected = ResumeInvocation(
                    provider: .codex, sessionId: try ProviderSessionId(rawValue: record.conversationID))
                #expect(decided.plan.resume == expected)
                let binding = try await reopened.binding()
                #expect(binding?.evidenceUnordered == false)
                #expect(!FileManager.default.fileExists(atPath: reopened.storeURL.path))
                try await closeLifecycleSafetyFiles(reopened)
            } catch {
                try? await closeLifecycleSafetyFiles(reopened)
                throw error
            }
        }
    }
}
