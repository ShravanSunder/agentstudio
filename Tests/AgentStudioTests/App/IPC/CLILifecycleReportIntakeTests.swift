import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import AgentStudioSessions
import AgentStudioTestHarness
import Foundation
import GRDB
import Testing

@testable import AgentStudio
@testable import AgentStudioCLIStore
@testable import AgentStudioCore

@Suite("CLI lifecycle intake prefix and parity")
struct CLILifecycleReportIntakeTests {
    @Test(
        "drained end envelopes preserve absent and unrecognized reasons exactly",
        arguments: [nil, "private future reason"] as [String?])
    func drainedReasonParity(reason: String?) async throws {
        try await withLifecycleIntakeFixture { fixture in
            let intake = fixture.intake()
            _ = try await intake.captureListenerReadyBoundary()
            let start = try await fixture.seed(fixture.record())
            #expect(
                try await intake.recordLive(
                    paneId: fixture.paneID, params: fixture.params(start.record, sequence: start.sequence)
                ).disposition == .admitted)
            let end = try await fixture.seed(
                fixture.record(sessionID: start.record.conversationID, event: .sessionEnd(reason: reason)))
            try await intake.takeIn(through: .stored(storeId: fixture.storeID, sequence: end.sequence))
            let fetched = try await fixture.binding()
            let binding = try #require(fetched)
            #expect(binding.providerEndReason == (reason == nil ? .notGiven : .unrecognized))
            #expect(binding.providerEndReasonText == reason)
            #expect(binding.providerEndedAt != nil)
            #expect(fixture.refusals.snapshot().isEmpty)
        }
    }

    @Test("historical start through S0 binds the exact session without an active source generation")
    func historicalStartHasRecordedProvenance() async throws {
        try await withLifecycleIntakeFixture { fixture in
            let record = fixture.record()
            let row = try await fixture.seed(record)
            let intake = fixture.intake()
            let boundary = try await intake.captureListenerReadyBoundary()
            #expect(boundary == .stored(storeId: fixture.storeID, sequence: row.sequence))
            try await intake.takeIn(through: boundary)
            let fetched = try await fixture.binding()
            let binding = try #require(fetched)
            #expect(binding.providerConversationId == record.conversationID)
            #expect(binding.startedFromHistoricalReport)
            #expect(!binding.evidenceUnordered)
            let state = try await fixture.state()
            #expect(state.mark == row.sequence)
            #expect(state.activeSources == 0)
            let query = try await fixture.adapter().readSessionState(
                paneId: fixture.paneID, params: .init(handle: "self"))
            #expect(query.sourceHealth == .ended)
            #expect(try await fixture.sameProviderLookVerdict() == .unknown(.startedFromHistoricalReport))
        }
    }

    @Test("live N drains its prefix in recorded order, skips a numeric gap and deduplicates its drained copy")
    func liveGapDrainsWithoutWaitingForMissingSequence() async throws {
        try await withLifecycleIntakeFixture { fixture in
            let intake = fixture.intake()
            _ = try await intake.captureListenerReadyBoundary()
            let first = try await fixture.seed(fixture.record(), sequence: 1)
            let second = try await fixture.seed(fixture.record(), sequence: 3)
            let params = fixture.params(second.record, sequence: second.sequence)
            #expect(try await intake.recordLive(paneId: fixture.paneID, params: params).disposition == .admitted)
            let fetched = try await fixture.binding()
            let binding = try #require(fetched)
            #expect(binding.providerConversationId == second.record.conversationID)
            #expect(!binding.startedFromHistoricalReport)
            let afterLive = try await fixture.state()
            #expect(afterLive.mark == 3)
            #expect(afterLive.bindings == 2)
            #expect(afterLive.operations == 2)
            try await intake.takeIn(through: .stored(storeId: fixture.storeID, sequence: 3))
            _ = try await intake.recordLive(paneId: fixture.paneID, params: params)
            #expect(try await fixture.state() == afterLive)
            #expect(first.sequence < second.sequence)
        }
    }

    @Test("refused version and malformed rows advance the prefix without blocking a valid row or leaking raw text")
    func refusedPrefixDoesNotBlockValidReport() async throws {
        try await withLifecycleIntakeFixture { fixture in
            let invalid = try await fixture.seed(fixture.record(event: .sessionEnd(reason: "private refusal text")))
            let refused = try await fixture.seed(fixture.record(version: "future-version"))
            let valid = try await fixture.seed(fixture.record())
            try await valueFromDedicatedThread {
                let writer = try CLIStore.openWriter(url: fixture.storeURL, channel: .debug).get()
                try writer.databaseQueue.write { database in
                    try database.execute(
                        sql: "UPDATE cli_lifecycle_report SET event_name='unknown-kind' WHERE sequence=?",
                        arguments: [invalid.sequence])
                }
            }
            let intake = fixture.intake()
            let boundary = try await intake.captureListenerReadyBoundary()
            try await intake.takeIn(through: boundary)
            let fetched = try await fixture.binding()
            #expect(fetched?.providerConversationId == valid.record.conversationID)
            let state = try await fixture.state()
            #expect(state.mark == valid.sequence)
            #expect(state.bindings == 1)
            let reasons = fixture.refusals.snapshot()
            #expect(reasons == [.invalidStoredRow, .qualificationRejected])
            #expect(!String(describing: reasons).contains("private refusal text"))
            #expect(refused.sequence < state.mark)
        }
    }

    @Test("a local transaction failure after the cursor write rolls back both cursor and Sessions effect")
    func cursorAndEffectAreOneCommit() async throws {
        try await withLifecycleIntakeFixture { fixture in
            let intake = fixture.intake()
            _ = try await intake.captureListenerReadyBoundary()
            let row = try await fixture.seed(fixture.record())
            let before = try await fixture.state()
            fixture.access.failNextCursorAdvance()
            await #expect(throws: (any Error).self) {
                _ = try await intake.recordLive(
                    paneId: fixture.paneID, params: fixture.params(row.record, sequence: row.sequence))
            }
            #expect(try await fixture.state() == before)
            #expect(
                try await intake.recordLive(
                    paneId: fixture.paneID, params: fixture.params(row.record, sequence: row.sequence)
                ).disposition == .admitted)
            let after = try await fixture.state()
            #expect(after.mark == row.sequence)
            #expect(after.bindings == 1)
            #expect(after.operations == 1)
        }
    }

    @Test("a lost CLI acknowledgment and app reopen never replay the durable handled prefix")
    func lostAcknowledgmentSurvivesReopen() async throws {
        try await withLifecycleIntakeFixture { fixture in
            let intake = fixture.intake()
            _ = try await intake.captureListenerReadyBoundary()
            let row = try await fixture.seed(fixture.record())
            let params = fixture.params(row.record, sequence: row.sequence)
            _ = try await intake.recordLive(paneId: fixture.paneID, params: params)
            let before = try await fixture.state()
            #expect(before.mark == row.sequence)
            #expect(before.bindings == 1)
            await fixture.close()
            let reopened = try await LifecycleIntakeFileFixture.make(rootURL: fixture.rootURL, paneID: fixture.paneID)
            do {
                let reopenedIntake = reopened.intake()
                let boundary = try await reopenedIntake.captureListenerReadyBoundary()
                try await reopenedIntake.takeIn(through: boundary)
                _ = try await reopenedIntake.recordLive(paneId: reopened.paneID, params: params)
                #expect(try await reopened.state() == before)
                await reopened.close()
            } catch {
                await reopened.close()
                throw error
            }
        }
    }

    @Test(
        "live and drained lifecycle qualification retain exact envelope fields and end-reason classification",
        arguments: ["codex", "claude-code"])
    func liveAndDrainShareQualification(provider: String) async throws {
        try await withLifecycleIntakeFixture { fixture in
            let intake = fixture.intake()
            _ = try await intake.captureListenerReadyBoundary()
            let start = try await fixture.seed(fixture.record(provider: provider))
            let live = fixture.params(start.record, sequence: start.sequence)
            #expect(try await intake.recordLive(paneId: fixture.paneID, params: live).disposition == .admitted)
            let reason = provider == "codex" ? "exit" : "prompt_input_exit"
            let end = try await fixture.seed(
                fixture.record(
                    sessionID: start.record.conversationID, event: .sessionEnd(reason: reason), provider: provider))
            try await intake.takeIn(through: .stored(storeId: fixture.storeID, sequence: end.sequence))
            let fetched = try await fixture.binding()
            let binding = try #require(fetched)
            #expect(binding.providerConversationId == live.event.conversationId)
            #expect(binding.providerIdentifier == live.provider.identifier)
            #expect(binding.providerEndReason == .personExit)
            #expect(binding.providerEndReasonText == reason)
            #expect(binding.providerEndedAt != nil)
            #expect(try await fixture.state().mark == end.sequence)
        }
    }

    @Test(
        "a retired pane and a foreign store receipt cannot change a binding; refusal only advances its own store prefix"
    )
    func retirementAndForeignStoreAreRefused() async throws {
        try await withLifecycleIntakeFixture { fixture in
            let intake = fixture.intake()
            _ = try await intake.captureListenerReadyBoundary()
            let row = try await fixture.seed(fixture.record())
            fixture.members.retire(fixture.paneID)
            try await intake.takeIn(through: .stored(storeId: fixture.storeID, sequence: row.sequence))
            #expect(try await fixture.state().mark == row.sequence)
            #expect(try await fixture.binding() == nil)
            #expect(fixture.refusals.snapshot() == [.retiredPane])
            let before = try await fixture.state()
            _ = try await intake.recordLive(
                paneId: fixture.paneID, params: fixture.params(row.record, sequence: 99, storeID: UUIDv7.generate()))
            #expect(try await fixture.state() == before)
            #expect(fixture.refusals.snapshot().last == .foreignStore)
        }
    }
}

func withLifecycleIntakeFixture(
    isolation: isolated (any Actor)? = #isolation,
    _ body: (LifecycleIntakeFileFixture) async throws -> Void
) async throws {
    let fixture = try await LifecycleIntakeFileFixture.make()
    do {
        try await body(fixture)
        await fixture.close()
        fixture.remove()
    } catch {
        await fixture.close()
        fixture.remove()
        throw error
    }
}
