import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("Bridge agent reveal admission and settlement", .serialized)
struct BridgePaneRevealActorTests {
    init() { installTestCoreAtomsIfNeeded() }

    @Test("production eligibility fails closed and retains one Open view item without page activation")
    func productionWaitsWithoutPageWork() async throws {
        let fixture = try BridgePaneRevealActorFixture()

        let operationID = try await fixture.admit()
        let settlement = try await fixture.awaitSettlement(operationID)

        #expect(settlement == .waitingInOpenView)
        #expect(
            await fixture.actor.retainedOpenViewItems(
                receiver: PaneId(existingUUID: fixture.navigation.receiver.paneId)
            ).count == 1)
        #expect(fixture.presentation.preparationCount == 0)
        #expect(fixture.presentation.activatedLocations.isEmpty)
        #expect(
            fixture.navigation.handler.record(for: fixture.navigation.receiver)?
                .openedDocument(at: fixture.location)?.retainedOpenViewItem?.target == fixture.target)
        await fixture.actor.shutdown()
    }

    @Test("unknown worktree is refused at admission without an operation or retained item")
    func unknownWorktreeIsUnsupported() async throws {
        let fixture = try BridgePaneRevealActorFixture()
        let unknown = try BridgeRevealFileTarget(
            worktree: UUIDv7.generate(), relativePath: fixture.target.relativePath,
            line: fixture.target.line
        )

        let result = try await fixture.actor.admitAgentReveal(
            receiver: PaneId(existingUUID: fixture.navigation.receiver.paneId),
            target: unknown, requestedBy: fixture.requester
        )

        #expect(result == .unsupportedTarget)
        #expect(
            await fixture.actor.retainedOpenViewItems(
                receiver: PaneId(existingUUID: fixture.navigation.receiver.paneId)
            ).isEmpty)
        await fixture.actor.shutdown()
    }

    @Test("human Open remains unavailable until the integrated activation owner is installed")
    func humanOpenIsNotInvokedByAgentPreparation() async throws {
        let fixture = try BridgePaneRevealActorFixture()

        do {
            _ = try await fixture.actor.openRetainedViewItem(
                receiver: PaneId(existingUUID: fixture.navigation.receiver.paneId),
                target: fixture.target
            )
            Issue.record("Human Open must remain unavailable in 2.3a")
        } catch let failure as BridgeLinkPortFailure {
            #expect(failure == .unavailable)
        }
        #expect(fixture.presentation.preparationCount == 0)
        #expect(fixture.presentation.activatedLocations.isEmpty)
        await fixture.actor.shutdown()
    }

    @Test("a final eligibility recheck that sees a draft or hidden receiver settles waiting")
    func eligibilityChangePreventsShown() async throws {
        let eligibility = BridgeScriptedAgentRevealEligibility(mode: .becameIneligible)
        let fixture = try BridgePaneRevealActorFixture(eligibility: eligibility)

        let operationID = try await fixture.admit()
        let settlement = try await fixture.awaitSettlement(operationID)

        #expect(settlement == .waitingInOpenView)
        #expect(await eligibility.activationCount == 1)
        #expect(fixture.presentation.activatedLocations.isEmpty)
        await fixture.actor.shutdown()
    }

    @Test("only a line-confirmed activation result can settle shown")
    func confirmedActivationSettlesShown() async throws {
        let eligibility = BridgeScriptedAgentRevealEligibility(mode: .shown)
        let fixture = try BridgePaneRevealActorFixture(eligibility: eligibility)

        let operationID = try await fixture.admit()
        let settlement = try await fixture.awaitSettlement(operationID)

        #expect(settlement == .shown)
        #expect(await eligibility.activationCount == 1)
        await fixture.actor.shutdown()
    }

    @Test("a close during a held retain fences the older reveal in atom and storage")
    func heldRetentionThenCloseDoesNotResurrect() async throws {
        let fixture = try BridgePaneRevealActorFixture(existingDocument: true)
        await fixture.storage.holdNextRetention()
        let operationID = try await fixture.admit()
        let dispatchedTarget = await fixture.storage.waitForRetentionDispatch()
        #expect(dispatchedTarget == fixture.target)

        #expect(
            await fixture.navigation.handler.closeFile(
                fixture.location, in: fixture.navigation.receiver
            ) == .applied)
        // The close fact has its Q9 ticket in the atom turn. The following
        // save capture takes a strictly newer ticket before leaving MainActor.
        let savedCloseTicket = fixture.navigation.store.bridgeWriteSequencer.nextTicket().value
        await fixture.storage.simulateUIClose(fixture.location, generation: savedCloseTicket)
        await fixture.storage.releaseRetention()

        #expect(try await fixture.awaitSettlement(operationID) == .superseded)
        #expect(
            fixture.navigation.handler.record(for: fixture.navigation.receiver)?
                .openedDocument(at: fixture.location) == nil)
        #expect(
            await fixture.actor.retainedOpenViewItems(
                receiver: PaneId(existingUUID: fixture.navigation.receiver.paneId)
            ).isEmpty)
        #expect(await fixture.actor.closeFloorEntryCount() == 0)
        await fixture.actor.shutdown()
    }

    @Test("a close between the prepared decision and MainActor apply rejects and recomputes")
    func closeAtPublicationBoundaryRejectsApply() async throws {
        let interlock = BridgeHeldRevealPublicationInterlock()
        let fixture = try BridgePaneRevealActorFixture(
            existingDocument: true, interlock: interlock
        )
        let operationID = try await fixture.admit()
        let decision = await interlock.waitForDecision()
        #expect(decision.receiver == fixture.navigation.receiver)
        #expect(decision.location == fixture.location)

        #expect(
            await fixture.navigation.handler.closeFile(
                fixture.location, in: fixture.navigation.receiver
            ) == .applied)
        let savedCloseTicket = fixture.navigation.store.bridgeWriteSequencer.nextTicket().value
        await fixture.storage.simulateUIClose(fixture.location, generation: savedCloseTicket)
        await interlock.release()

        #expect(try await fixture.awaitSettlement(operationID) == .superseded)
        #expect(
            fixture.navigation.handler.record(for: fixture.navigation.receiver)?
                .openedDocument(at: fixture.location) == nil)
        await fixture.actor.shutdown()
    }

    @Test("an unrelated UI edit causes recompute and keeps the admitted reveal")
    func unrelatedEditDoesNotDropReveal() async throws {
        let interlock = BridgeHeldRevealPublicationInterlock()
        let fixture = try BridgePaneRevealActorFixture(interlock: interlock)
        let operationID = try await fixture.admit()
        let decision = await interlock.waitForDecision()
        #expect(decision.receiver == fixture.navigation.receiver)
        #expect(decision.location == fixture.location)

        var edited = try #require(fixture.navigation.handler.record(for: fixture.navigation.receiver))
        edited.filesFilter = .openedDocuments
        fixture.navigation.store.bridgeNavigationAtom.setRecord(edited, for: fixture.navigation.receiver)
        await interlock.release()

        #expect(try await fixture.awaitSettlement(operationID) == .waitingInOpenView)
        let record = try #require(fixture.navigation.handler.record(for: fixture.navigation.receiver))
        #expect(record.filesFilter == .openedDocuments)
        #expect(record.openedDocument(at: fixture.location)?.retainedOpenViewItem != nil)
        await fixture.actor.shutdown()
    }

    @Test("a new reveal after close is new intent and may append the document")
    func laterRevealAfterCloseAppends() async throws {
        let fixture = try BridgePaneRevealActorFixture(existingDocument: true)
        #expect(
            await fixture.navigation.handler.closeFile(
                fixture.location, in: fixture.navigation.receiver
            ) == .applied)
        let savedCloseTicket = fixture.navigation.store.bridgeWriteSequencer.nextTicket().value
        await fixture.storage.simulateUIClose(fixture.location, generation: savedCloseTicket)

        let operationID = try await fixture.admit()
        #expect(try await fixture.awaitSettlement(operationID) == .waitingInOpenView)
        #expect(
            fixture.navigation.handler.record(for: fixture.navigation.receiver)?
                .openedDocument(at: fixture.location) != nil)
        await fixture.actor.shutdown()
    }

    @Test("a close during admission preview precedes the accepted reveal ticket")
    func previewCloseThenAdmitIsNewIntent() async throws {
        let fixture = try BridgePaneRevealActorFixture(existingDocument: true)
        await fixture.storage.holdNextAdmissionPreview()
        let admission = Task { try await fixture.admit() }
        let previewedTarget = await fixture.storage.waitForAdmissionPreview()
        #expect(previewedTarget == fixture.target)

        #expect(
            await fixture.navigation.handler.closeFile(
                fixture.location, in: fixture.navigation.receiver
            ) == .applied)
        let savedCloseTicket = fixture.navigation.store.bridgeWriteSequencer.nextTicket().value
        await fixture.storage.simulateUIClose(fixture.location, generation: savedCloseTicket)
        await fixture.storage.releaseAdmissionPreview()

        let operationID = try await admission.value
        #expect(try await fixture.awaitSettlement(operationID) == .waitingInOpenView)
        #expect(
            try #require(await fixture.storage.retainedGeneration(for: fixture.location))
                > savedCloseTicket)
        #expect(
            fixture.navigation.handler.record(for: fixture.navigation.receiver)?
                .openedDocument(at: fixture.location)?.retainedOpenViewItem != nil)
        await fixture.actor.shutdown()
    }

    @Test("a close after ticket capture is retained by the provisional keyed reveal")
    func closeDuringTicketHopSupersedesOlderReveal() async throws {
        let interlock = BridgeHeldRevealAdmissionTicketInterlock()
        let fixture = try BridgePaneRevealActorFixture(
            existingDocument: true, interlock: interlock
        )
        let admission = Task { try await fixture.admit() }
        let captured = await interlock.waitForCapturedTicket()
        #expect(captured.receiver == fixture.navigation.receiver)
        #expect(captured.location == fixture.location)

        #expect(
            await fixture.navigation.handler.closeFile(
                fixture.location, in: fixture.navigation.receiver
            ) == .applied)
        let savedCloseTicket = fixture.navigation.store.bridgeWriteSequencer.nextTicket().value
        await interlock.release()

        let operationID = try await admission.value
        #expect(try await fixture.awaitSettlement(operationID) == .superseded)
        #expect(
            fixture.navigation.handler.record(for: fixture.navigation.receiver)?
                .openedDocument(at: fixture.location) == nil)
        await fixture.storage.simulateUIClose(fixture.location, generation: savedCloseTicket)
        #expect(
            await fixture.actor.retainedOpenViewItems(
                receiver: PaneId(existingUUID: fixture.navigation.receiver.paneId)
            ).isEmpty)
        #expect(await fixture.actor.closeFloorEntryCount() == 0)
        await fixture.actor.shutdown()
    }

    @Test("shutdown during the ticket hop discards provisional registration")
    func shutdownDuringTicketHopRejectsAdmission() async throws {
        let interlock = BridgeHeldRevealAdmissionTicketInterlock()
        let fixture = try BridgePaneRevealActorFixture(interlock: interlock)
        let admission = Task { try await fixture.admit() }
        let captured = await interlock.waitForCapturedTicket()
        #expect(captured.receiver == fixture.navigation.receiver)
        #expect(captured.location == fixture.location)

        await fixture.actor.shutdown()
        await interlock.release()

        do {
            _ = try await admission.value
            Issue.record("Admission must reject after shutdown")
        } catch let failure as BridgeLinkPortFailure {
            #expect(failure == .unavailable)
        }
        #expect(await fixture.actor.closeFloorEntryCount() == 0)
    }

    @Test("caller cancellation during the ticket hop discards provisional registration")
    func cancellationDuringTicketHopRejectsAdmission() async throws {
        let interlock = BridgeHeldRevealAdmissionTicketInterlock()
        let fixture = try BridgePaneRevealActorFixture(interlock: interlock)
        let admission = Task { try await fixture.admit() }
        let captured = await interlock.waitForCapturedTicket()
        #expect(captured.receiver == fixture.navigation.receiver)
        #expect(captured.location == fixture.location)

        admission.cancel()
        await interlock.release()

        do {
            _ = try await admission.value
            Issue.record("Cancelled admission must not return an operation ID")
        } catch is CancellationError {
            #expect(await fixture.actor.closeFloorEntryCount() == 0)
        }
        await fixture.actor.shutdown()
    }

    @Test("close floors are dropped after the last reveal of their document settles")
    func closeFloorIsBounded() async throws {
        let interlock = BridgeHeldRevealPublicationInterlock()
        let fixture = try BridgePaneRevealActorFixture(existingDocument: true, interlock: interlock)
        let operationID = try await fixture.admit()
        let decision = await interlock.waitForDecision()
        #expect(decision.receiver == fixture.navigation.receiver)
        #expect(decision.location == fixture.location)
        #expect(
            await fixture.navigation.handler.closeFile(
                fixture.location, in: fixture.navigation.receiver
            ) == .applied)
        await fixture.actor.awaitIngressBarrier()
        #expect(await fixture.actor.closeFloorEntryCount() == 1)
        await interlock.release()

        #expect(try await fixture.awaitSettlement(operationID) == .superseded)
        #expect(await fixture.actor.closeFloorEntryCount() == 0)
        await fixture.actor.shutdown()
    }

    @Test("shutdown settles queued admission once and preserves a dispatched terminal for late await")
    func shutdownSettlesWithoutLosingTerminals() async throws {
        let fixture = try BridgePaneRevealActorFixture()
        await fixture.storage.holdNextRetention()
        let firstID = try await fixture.admit()
        let dispatchedTarget = await fixture.storage.waitForRetentionDispatch()
        #expect(dispatchedTarget == fixture.target)
        let secondID = try await fixture.admit()

        let shutdown = Task { await fixture.actor.shutdown() }
        #expect(try await fixture.awaitSettlement(secondID) == .unavailable)
        let repeatedShutdown = Task { await fixture.actor.shutdown() }
        await fixture.storage.releaseRetention()
        await shutdown.value
        await repeatedShutdown.value
        #expect(try await fixture.awaitSettlement(firstID) == .waitingInOpenView)
        do {
            _ = try await fixture.awaitSettlement(firstID)
            Issue.record("A terminal settlement was delivered twice")
        } catch let failure as BridgeLinkPortFailure {
            #expect(failure == .unavailable)
        }
    }
}
