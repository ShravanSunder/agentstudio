import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestHarness
import Foundation
import Testing

@testable import AgentStudioTerminal

/// F6 (review round 1, 2026-10-02; PD item 13 "Ending ordered for
/// SessionStart"): the accumulator's ordered end follows an in-flight
/// restore aggregate before the projector clears the phase.
///
/// Modeled on `GhosttyRouterRestorePhaseEndDuringDrainTests`: a real surface
/// registered in `SurfaceManager`, a real
/// `Ghostty.ActionRouter.localActionAccumulator.offer` scheduling a real
/// drain through the real scheduler, and a `HeldStep` parking that real
/// drain deterministically at its one suspension point (submitting the
/// aggregate) instead of racing it against the end. Unlike that suite, this
/// one also needs the real `TerminalActivityRouter.resumedSessionStartSink`
/// under test, so this binds its own single global sink (the binding is
/// one-sink, not fan-out -- confirmed by reading
/// `GhosttyTerminalActivityInputBinding.bind` directly) and forwards every
/// input to a real router's `consumeTerminalActivityInput`, with the
/// `.aggregate` arm's `HeldStep` wrapped around that forward, not
/// substituting for it.
@MainActor
@Suite("Ghostty router resumed SessionStart restore-phase end", .serialized)
struct GhosttyRouterResumedSessionStartEndTests {
    private enum DrainFact: Sendable, Equatable {
        case aggregateDelivered
        case restorePhaseEnded(RestoreGeneration)
    }

    private func vocabulary() -> FactVocabulary<UUID, DrainFact> {
        FactVocabulary(
            describeScope: { $0.uuidString },
            describeFact: { String(describing: $0) },
            isClosing: { _, fact in
                if case .restorePhaseEnded = fact { return true }
                return false
            }
        )
    }

    @Test(
        "a matched resumed SessionStart ends the phase after in-flight restore output, so no window opens"
    )
    func matchedStartEndsBeforePendingOutputIsFolded() async throws {
        let surfaceID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let generation = RestoreGeneration(rawValue: 21)
        let bindingID = UUIDv7.generate()
        let sessionIdText = UUIDv7.generate().uuidString
        let invocation = ResumeInvocation(provider: .codex, sessionId: try ProviderSessionId(rawValue: sessionIdText))

        let surface = Ghostty.SurfaceView(
            managedSurfaceID: surfaceID, appCommandDispatcher: ResumedSessionStartEndNoOpAppCommandDispatcher())
        guard
            case .success = SurfaceManager.shared.acceptCreatedSurface(
                surface, metadata: SurfaceMetadata(paneId: paneID))
        else {
            Issue.record("expected SurfaceManager.shared to accept the test surface")
            throw ResumedSessionStartEndTestFailure.setupDidNotSucceed
        }
        SurfaceManager.shared.attach(surfaceID, to: paneID)
        defer { SurfaceManager.shared.destroy(surfaceID) }

        // A directly-injected projector, so this test can read its exposed
        // `scheduledTimerCount` -- the same signal
        // `TerminalActivityProjectorRestorePhaseTests` already uses to prove
        // "no window opened" (a window's admission always schedules its own
        // close timer).
        let projector = TerminalActivityProjector()
        let router = TerminalActivityRouter(
            bus: EventBus<RuntimeEnvelope>(),
            activityAtom: TerminalActivityAtom(outputBurstThreshold: 30),
            projector: projector,
            surfaceIDForPaneID: { _ in surfaceID }
        )

        let source = LocalFactSource(vocabulary: vocabulary())
        let recorder = try source.attach()
        let suspensionPoint = HeldStep<Void>("real drain suspended submitting restore-time output")

        Ghostty.ActionRouter.bindTerminalActivityInput(
            id: bindingID,
            context: { _ in
                TerminalActivityProjectionContext(
                    isAttended: false, isAgentClassified: false, outputBurstThreshold: 30)
            },
            sink: { input in
                if case .aggregate = input {
                    // The real suspension point: parks the real drain Task
                    // here until the test releases it, then forwards to the
                    // real router exactly as production delivery does.
                    try? await suspensionPoint.arrive(())
                    await router.consumeTerminalActivityInput(input)
                    source.sink(surfaceID, .aggregateDelivered)
                } else {
                    await router.consumeTerminalActivityInput(input)
                    if case .orderedControl(let surfaceID, _, _, .restorePhaseEnded(let generation)) = input {
                        source.sink(surfaceID, .restorePhaseEnded(generation))
                    }
                }
            }
        )
        defer { Ghostty.ActionRouter.unbindTerminalActivityInput(id: bindingID) }
        defer { Ghostty.ActionRouter.retireLocalActions(for: surfaceID) }

        // Arrange -- arm through the real production entry point, which
        // waits for the binding above before arming.
        let acknowledgment = await Ghostty.ActionRouter.armRestorePhase(
            paneID: paneID, restoreGeneration: generation, resumeInvocation: invocation)
        #expect(acknowledgment == .armed)
        #expect(await projector.scheduledTimerCount == 0)

        // Restore-time output schedules a real drain through the real
        // scheduler. It will suspend inside the bound sink's `.aggregate`
        // arm, above, before ever reaching the projector.
        Ghostty.ActionRouter.localActionAccumulator.offer(
            .scrollbar(ScrollbarState(top: 0, bottom: 10, total: 10), observedAtMilliseconds: 1000),
            for: surfaceID
        )
        _ = try await suspensionPoint.firstArrival()

        // The matched start latches an end behind the in-flight aggregate.
        await router.resumedSessionStartSink(paneID, "codex", sessionIdText)
        #expect(await projector.isRestorePhaseActive(paneID: paneID))

        // Release the aggregate, then observe the correlated ordered end.
        suspensionPoint.release()
        _ = try await recorder.expectNext(
            in: surfaceID,
            where: {
                if case .aggregateDelivered = $0 { return true }
                return false
            },
            "aggregateDelivered"
        )
        try await recorder.expectNext(in: surfaceID, .restorePhaseEnded(generation))

        #expect(await projector.isRestorePhaseActive(paneID: paneID) == false)
        #expect(await projector.scheduledTimerCount == 0)
        try await recorder.finish()
    }
}

private enum ResumedSessionStartEndTestFailure: Error {
    case setupDidNotSucceed
}

/// No-op dispatcher used only to satisfy `Ghostty.SurfaceView`'s bare test
/// initializer, matching every other test file in this directory that needs
/// one.
@MainActor
private final class ResumedSessionStartEndNoOpAppCommandDispatcher: AppCommandDispatching {
    func dispatch(_: AppCommand) -> Bool { false }
    func dispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) {}
    func canDispatch(_: AppCommand) -> Bool { false }
    func canDispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool { false }
    func bridgePaneCommandTarget(worktreeId _: UUID) -> BridgePaneCommandTarget? { nil }
    func dispatchMovePaneToTab(sourcePaneId _: UUID, sourceTabId _: UUID?, targetTabId _: UUID) {}
}
