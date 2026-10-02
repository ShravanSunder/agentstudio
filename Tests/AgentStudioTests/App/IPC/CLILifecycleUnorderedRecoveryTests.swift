import AgentStudioCLIStore
import AgentStudioInfrastructure
import AgentStudioTestHarness
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@Suite("CLI lifecycle unordered recovery")
struct CLILifecycleUnorderedRecoveryTests {
    @Test("unsequenced effect and its immediate successful-read fence share one atomic Sessions transaction")
    func successfulReadFencesUnsequencedAdmissionAtomically() async throws {
        try await withLifecycleIntakeFixture { fixture in
            let intake = fixture.intake()
            _ = try await intake.captureListenerReadyBoundary()
            let old = try await fixture.seed(fixture.record())
            let unordered = fixture.record()
            let before = try await fixture.state()
            fixture.access.failNextUnorderedAdmission()
            await #expect(throws: (any Error).self) {
                _ = try await intake.recordLive(paneId: fixture.paneID, params: fixture.params(unordered))
            }
            #expect(try await fixture.state() == before)
            #expect(try await fixture.binding() == nil)
            #expect(
                try await intake.recordLive(paneId: fixture.paneID, params: fixture.params(unordered)).disposition
                    == .admitted)
            let fetched = try await fixture.binding()
            #expect(fetched?.providerConversationId == unordered.conversationID)
            #expect(fetched?.evidenceUnordered == true)
            #expect(fetched?.unorderedFenceSequence == old.sequence)
            #expect(try await fixture.state().mark == 0)
            #expect(try await fixture.sameProviderLookVerdict() == .unknown(.evidenceUnordered))
        }
    }

    @Test("stored A held across unsequenced B cannot replace B or regain a candidate from a same-provider look")
    func olderStoredStartIsRefusedAtFence() async throws {
        try await withLifecycleIntakeFixture { fixture in
            let intake = fixture.intake()
            _ = try await intake.captureListenerReadyBoundary()
            let old = try await fixture.seed(fixture.record())
            let unordered = fixture.record()
            try await withUnavailableLifecycleStore(fixture) {
                let admission = try await intake.recordLive(
                    paneId: fixture.paneID, params: fixture.params(unordered))
                #expect(admission.disposition == .admitted)
            }
            let before = try await fixture.binding()
            #expect(before?.providerConversationId == unordered.conversationID)
            #expect(before?.evidenceUnordered == true)
            #expect(before?.unorderedFenceSequence == nil)
            try await intake.takeIn(through: .stored(storeId: fixture.storeID, sequence: old.sequence))
            let after = try await fixture.binding()
            #expect(after?.bindingGenerationId == before?.bindingGenerationId)
            #expect(after?.providerConversationId == unordered.conversationID)
            #expect(after?.unorderedFenceSequence == old.sequence)
            #expect(after?.evidenceUnordered == true)
            #expect(fixture.refusals.snapshot() == [.supersededByUnorderedReport])
            #expect(try await fixture.sameProviderLookVerdict() == .unknown(.evidenceUnordered))
        }
    }

    @Test("awaiting-fence B persists across app close and reopen before a first successful store read")
    func awaitingFenceSurvivesReopen() async throws {
        try await withLifecycleIntakeFixture { fixture in
            let intake = fixture.intake()
            _ = try await intake.captureListenerReadyBoundary()
            let old = try await fixture.seed(fixture.record())
            let unordered = fixture.record()
            try await withUnavailableLifecycleStore(fixture) {
                _ = try await intake.recordLive(paneId: fixture.paneID, params: fixture.params(unordered))
                let fetched = try await fixture.binding()
                #expect(fetched?.evidenceUnordered == true)
                #expect(fetched?.unorderedFenceSequence == nil)
                await fixture.close()
            }
            let reopened = try await LifecycleIntakeFileFixture.make(rootURL: fixture.rootURL, paneID: fixture.paneID)
            do {
                let persisted = try await reopened.binding()
                #expect(persisted?.providerConversationId == unordered.conversationID)
                #expect(persisted?.evidenceUnordered == true)
                #expect(persisted?.unorderedFenceSequence == nil)
                let reopenedIntake = reopened.intake()
                let boundary = try await reopenedIntake.captureListenerReadyBoundary()
                try await reopenedIntake.takeIn(through: boundary)
                let after = try await reopened.binding()
                #expect(after?.providerConversationId == unordered.conversationID)
                #expect(after?.unorderedFenceSequence == old.sequence)
                #expect(try await reopened.sameProviderLookVerdict() == .unknown(.evidenceUnordered))
                await reopened.close()
            } catch {
                await reopened.close()
                throw error
            }
        }
    }

    @Test("C committed after B but before the first fence read is a conservative missed recovery")
    func reportBetweenAdmissionAndFenceIsRefused() async throws {
        try await withLifecycleIntakeFixture { fixture in
            let intake = fixture.intake()
            _ = try await intake.captureListenerReadyBoundary()
            _ = try await fixture.seed(fixture.record())
            let unordered = fixture.record()
            try await withUnavailableLifecycleStore(fixture) {
                _ = try await intake.recordLive(paneId: fixture.paneID, params: fixture.params(unordered))
            }
            let newerButBeforeFence = try await fixture.seed(fixture.record())
            try await intake.takeIn(through: .stored(storeId: fixture.storeID, sequence: newerButBeforeFence.sequence))
            let fetched = try await fixture.binding()
            #expect(fetched?.providerConversationId == unordered.conversationID)
            #expect(fetched?.unorderedFenceSequence == newerButBeforeFence.sequence)
            #expect(fixture.refusals.snapshot() == [.supersededByUnorderedReport, .supersededByUnorderedReport])
            #expect(try await fixture.sameProviderLookVerdict() == .unknown(.evidenceUnordered))
        }
    }

    @Test(
        "a sequenced report strictly above the durable fence clears ordering atomically and names only its own session")
    func reportAfterFenceRestoresOrderedEvidence() async throws {
        try await withLifecycleIntakeFixture { fixture in
            let intake = fixture.intake()
            _ = try await intake.captureListenerReadyBoundary()
            let old = try await fixture.seed(fixture.record())
            try await withUnavailableLifecycleStore(fixture) {
                _ = try await intake.recordLive(paneId: fixture.paneID, params: fixture.params(fixture.record()))
            }
            try await intake.takeIn(through: .stored(storeId: fixture.storeID, sequence: old.sequence))
            let recovery = try await fixture.seed(fixture.record())
            #expect(recovery.sequence > old.sequence)
            _ = try await intake.recordLive(
                paneId: fixture.paneID, params: fixture.params(recovery.record, sequence: recovery.sequence))
            let fetched = try await fixture.binding()
            #expect(fetched?.providerConversationId == recovery.record.conversationID)
            #expect(fetched?.evidenceUnordered == false)
            #expect(fetched?.unorderedFenceSequence == nil)
            #expect(try await fixture.state().mark == recovery.sequence)
            let sessionID = try ProviderSessionId(rawValue: recovery.record.conversationID)
            #expect(
                try await fixture.sameProviderLookVerdict()
                    == .interruptedCandidate(.init(provider: .codex, sessionId: sessionID)))
        }
    }
}

/// Only this fixture's closed CLI connection is moved; local.sqlite remains writable.
private func withUnavailableLifecycleStore(
    _ fixture: LifecycleIntakeFileFixture, body: () async throws -> Void
) async throws {
    let savedURL = fixture.rootURL.appending(path: "held-cli.sqlite")
    try await valueFromDedicatedThread { try FileManager.default.moveItem(at: fixture.storeURL, to: savedURL) }
    do {
        try await body()
        try await valueFromDedicatedThread { try FileManager.default.moveItem(at: savedURL, to: fixture.storeURL) }
    } catch {
        try? await valueFromDedicatedThread { try FileManager.default.moveItem(at: savedURL, to: fixture.storeURL) }
        throw error
    }
}
