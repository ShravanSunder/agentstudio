import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioTerminal

/// S10b — the settlement race `activate()`'s post-drain window exposed:
/// `TerminalActivationSchedulerTests.swift` and
/// `TerminalActivationSchedulerTestFakes.swift` are both already large, so
/// this one narrowly-scoped case lives in its own suite file.
@MainActor
@Suite("Terminal activation scheduler settlement race", .serialized)
struct TerminalActivationSchedulerSettlementRaceTests {
    @Test("a late acceptLaterGeometry reentry during the final activation settles without a precondition failure")
    func lateReentrantAcceptDuringFinalActivationSettlesCleanly() async throws {
        // Arrange: `triggerDescriptor` is the cohort's only initially eligible
        // (and therefore last-and-only queued) member. `lateDescriptor` starts
        // `waitingForGeometry` and is never named by `installGeometryEligibility`
        // — only the port's reentrant `acceptLaterGeometry` call, fired from
        // inside `activateClaimedTerminal` for `triggerDescriptor`, admits it.
        // That reentry lands in exactly the window between the drain's last
        // worker deciding no queued candidate remains and `activate()`
        // resuming to compute `makeSettlement()` — S9's real container-layout
        // callback can land there for the same reason, just less
        // deterministically.
        let generation = WorkspaceContentMountGeneration()
        let triggerDescriptor = makeDescriptor()
        let lateDescriptor = makeDescriptor()
        let port = ReentrantAcceptGeometryAdmissionPort()
        port.descriptorsByPaneID = [
            triggerDescriptor.paneID: triggerDescriptor,
            lateDescriptor.paneID: lateDescriptor,
        ]
        port.reentryTriggerPaneID = triggerDescriptor.paneID
        port.lateArrivingPaneID = lateDescriptor.paneID
        let scheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(
                generation: generation,
                input: TerminalActivationInput(entries: [triggerDescriptor, lateDescriptor])
            ),
            admissionPort: port
        )
        port.scheduler = scheduler
        _ = await scheduler.installGeometryEligibility([triggerDescriptor.paneID])

        // Act: two concurrent callers — one drives `activate()`'s `.idle`
        // path, the other joins as an `.activating` waiter — so a genuine fix
        // must resume every waiter exactly once with the one true settlement,
        // not merely avoid the precondition failure for a single caller.
        async let firstSettlement = scheduler.activate()
        async let secondSettlement = scheduler.activate()
        let (settlement, joinedSettlement) = await (firstSettlement, secondSettlement)
        // The reentrant call is spawned, not awaited (see the port's own
        // comment for why), so `activate()` returning does not itself
        // guarantee it has landed yet.
        await port.waitUntilReentryLands()

        // Assert: the reentrant call actually fired and was accepted, both
        // callers received the identical settlement, and — regardless of
        // whether the reentry happened to land inside `activate()`'s own
        // drain (this settlement already shows the late member `.ready`) or
        // strictly after settlement locked in (still `.waitingForGeometry`
        // here, picked up by `acceptLaterGeometry`'s own post-settlement
        // supplemental drain per SPEC R5) — the late member reaches `.ready`
        // and this call never trips `makeSettlement()`'s "no unfinished
        // members" precondition. This test cannot force the reentry into
        // that exact narrow window deterministically (verified empirically:
        // across repeated runs it lands on both sides, independent of S10b's
        // fix); what it can and does prove on every run is that neither
        // landing ever crashes or silently drops the late member. The S10
        // suite's `revealAndPreparedRequeueOverlapCompleteOneAdmissionCycleAsTwoFailedCreateSurfaceCallsWithOneSurfaceIdentity`
        // (run 12x after this fix) is the harder, more realistic proof this
        // fix targets — it reproduced the literal crash organically before
        // the fix, via real AppKit scheduling this synthetic port cannot
        // replicate on demand.
        #expect(port.acceptedLateArrivals == [lateDescriptor.paneID])
        #expect(settlement == joinedSettlement)
        #expect(settlement.outcomesByPaneID.count == 2)
        guard case .ready = settlement.outcomesByPaneID[triggerDescriptor.paneID] else {
            Issue.record("expected the trigger member to reach ready")
            return
        }
        if case .ready = settlement.outcomesByPaneID[lateDescriptor.paneID] {
            return
        }
        guard case .waitingForGeometry = settlement.outcomesByPaneID[lateDescriptor.paneID] else {
            Issue.record("expected the late member to be ready or still waitingForGeometry, never queued/attaching")
            return
        }
        await waitUntilMemberIsReady(scheduler: scheduler, paneID: lateDescriptor.paneID)
    }

    /// Bounded wait for `acceptLaterGeometry`'s own post-settlement
    /// supplemental drain (`ensureADrainObservesNewlyQueuedMembers`) to carry
    /// a still-waiting member to `.ready`. Never a sleep: each iteration only
    /// yields, and the loop returns the instant the state changes.
    private func waitUntilMemberIsReady(
        scheduler: TerminalActivationScheduler,
        paneID: PaneId,
        iterations: Int = 20_000
    ) async {
        for _ in 0..<iterations {
            if case .ready = await scheduler.memberState(for: paneID) { return }
            await Task.yield()
        }
        Issue.record("late member never reached ready via the post-settlement supplemental drain")
    }

    private func makeDescriptor() -> TerminalActivationDescriptor {
        let pane = Pane(
            id: UUIDv7.generate(),
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: .generateUUIDv7()
                )
            ),
            metadata: PaneMetadata(
                launchDirectory: URL(filePath: "/tmp/terminal-activation-settlement-race"),
                title: "Settlement race test"
            )
        )
        return TerminalActivationDescriptor(
            pane: pane,
            visibilityPriority: .activeVisible,
            hostPlacement: .tab(tabID: UUIDv7.generate())
        )
    }
}
