import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import AgentStudioTestHarness
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioSessions
@testable import AgentStudioTerminal

@Suite("Restore Sessions producers")
struct RestoreSessionsProducerTests {
    @Test("a lifecycle binding trigger follows its real SQLite commit, never the pending hook")
    func bindingTriggerFollowsCommit() async throws {
        let fixture = try AppResumeSessionsFixture()
        let ingestion = fixture.makeIngestion()
        let ledger = RestoreSessionsTriggerLedger()
        let adapter = resumeProducerAdapter(ingestion: ingestion, fixture: fixture, ledger: ledger)
        let hold = HeldStep<Void>("provider start before Sessions transaction")
        defer { hold.retire() }
        fixture.access.holdNextWrite(hold)
        let startParams = try fixture.event(.sessionStart)
        let start = Task {
            try await adapter.recordProviderEvent(
                paneId: fixture.paneId, params: startParams, provenance: .matchingPane)
        }
        do {
            _ = try await hold.firstArrival()
            #expect(ledger.snapshot().isEmpty)
            hold.release()
            #expect(try await start.value.disposition == .admitted)
            let committed = try #require(ledger.snapshot().first)
            #expect(committed.kind == .bindingChanged)
            #expect(committed.sessionId == fixture.sessionId)
            #expect(committed.bindingId != nil)
            #expect(!committed.ended)
            let endParams = try fixture.event(.sessionEnd)
            #expect(
                try await adapter.recordProviderEvent(
                    paneId: fixture.paneId, params: endParams, provenance: .matchingPane
                ).disposition == .admitted)
            let lifecycleTriggerKinds = ledger.snapshot().map { $0.kind }
            #expect(lifecycleTriggerKinds == [.bindingChanged, .bindingChanged])
            #expect(ledger.snapshot().last?.ended == true)
            await ingestion.finish()
        } catch {
            hold.retire()
            _ = try? await start.value
            await ingestion.finish()
            throw error
        }
    }

    @Test("a committed agent message requests a look once and replay adds no trigger")
    func messageReplayDoesNotRetrigger() async throws {
        let fixture = try AppResumeSessionsFixture()
        let ingestion = fixture.makeIngestion()
        let ledger = RestoreSessionsTriggerLedger()
        let adapter = resumeProducerAdapter(ingestion: ingestion, fixture: fixture, ledger: ledger)
        do {
            let start = try fixture.event(.sessionStart)
            _ = try await adapter.recordProviderEvent(paneId: fixture.paneId, params: start, provenance: .matchingPane)
            let message = IPCSessionMessageParams(
                handle: fixture.paneId.uuidString, text: "turn complete", correlationId: UUIDv7.generate())
            _ = try await adapter.recordAgentMessage(paneId: fixture.paneId, params: message)
            let afterCommit = ledger.snapshot()
            let committedTriggerKinds = afterCommit.map { $0.kind }
            #expect(committedTriggerKinds == [.bindingChanged, .agentMessage])
            #expect(afterCommit.last?.messages == 1)
            _ = try await adapter.recordAgentMessage(paneId: fixture.paneId, params: message)
            #expect(ledger.snapshot() == afterCommit)
            await ingestion.finish()
        } catch {
            await ingestion.finish()
            throw error
        }
    }

    @Test("an admitted stop hook requests foreground refresh without rebinding")
    func activityHookRefreshesWithoutRebinding() async throws {
        let fixture = try AppResumeSessionsFixture()
        let ingestion = fixture.makeIngestion()
        let ledger = RestoreSessionsTriggerLedger()
        let adapter = resumeProducerAdapter(ingestion: ingestion, fixture: fixture, ledger: ledger)
        do {
            let start = try fixture.event(.sessionStart)
            _ = try await adapter.recordProviderEvent(paneId: fixture.paneId, params: start, provenance: .matchingPane)
            let before = try await fixture.snapshot()
            let stop = try fixture.event(.stop)
            #expect(
                try await adapter.recordProviderEvent(paneId: fixture.paneId, params: stop, provenance: .matchingPane)
                    .disposition == .admitted)
            let after = try await fixture.snapshot()
            #expect(after.currentBinding?.bindingGenerationId == before.currentBinding?.bindingGenerationId)
            let activityTriggerKinds = ledger.snapshot().map { $0.kind }
            #expect(activityTriggerKinds == [.bindingChanged, .agentMessage])
            await ingestion.finish()
        } catch {
            await ingestion.finish()
            throw error
        }
    }

    @Test("an exact-version refusal has no binding trigger or foreground side effect")
    func refusedHookCannotTriggerLook() async throws {
        let fixture = try AppResumeSessionsFixture()
        let ingestion = fixture.makeIngestion()
        let ledger = RestoreSessionsTriggerLedger()
        let adapter = resumeProducerAdapter(ingestion: ingestion, fixture: fixture, ledger: ledger)
        do {
            let params = try fixture.event(.sessionStart, version: "not-qualified")
            #expect(
                try await adapter.recordProviderEvent(paneId: fixture.paneId, params: params, provenance: .matchingPane)
                    .disposition != .admitted)
            #expect(ledger.snapshot().isEmpty)
            let snapshot = try await fixture.snapshot()
            #expect(snapshot.currentBinding == nil)
            await ingestion.finish()
        } catch {
            await ingestion.finish()
            throw error
        }
    }
}
