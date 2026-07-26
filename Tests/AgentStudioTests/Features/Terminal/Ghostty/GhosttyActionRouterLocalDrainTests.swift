import Testing

@testable import AgentStudio

@MainActor
extension GhosttyActionRouterTests {
    @Test("mounted host lifetime validation accepts matching surface and pane identities")
    func mountedHostLifetimeValidationAcceptsMatchingIdentities() {
        let surfaceID = UUIDv7.generate()

        #expect(
            TerminalLocalActionDrainHostAccess.isMountedSurfaceLifetimeValid(
                surfaceID: surfaceID,
                managedSurfaceID: surfaceID,
                paneID: UUIDv7.generate()
            )
        )
    }

    @Test("mounted host lifetime validation rejects a missing surface")
    func mountedHostLifetimeValidationRejectsMissingSurface() {
        #expect(
            !TerminalLocalActionDrainHostAccess.isMountedSurfaceLifetimeValid(
                surfaceID: UUIDv7.generate(),
                managedSurfaceID: nil,
                paneID: UUIDv7.generate()
            )
        )
    }

    @Test("mounted host lifetime validation rejects a replaced surface")
    func mountedHostLifetimeValidationRejectsReplacedSurface() {
        #expect(
            !TerminalLocalActionDrainHostAccess.isMountedSurfaceLifetimeValid(
                surfaceID: UUIDv7.generate(),
                managedSurfaceID: UUIDv7.generate(),
                paneID: UUIDv7.generate()
            )
        )
    }

    @Test("mounted host lifetime validation rejects a missing pane")
    func mountedHostLifetimeValidationRejectsMissingPane() {
        let surfaceID = UUIDv7.generate()

        #expect(
            !TerminalLocalActionDrainHostAccess.isMountedSurfaceLifetimeValid(
                surfaceID: surfaceID,
                managedSurfaceID: surfaceID,
                paneID: nil
            )
        )
    }

    @Test("local drain with runtime writes host cache runtime batch and activity")
    func localDrainWithRuntimePreservesDeliveryPaths() async throws {
        let surfaceID = UUIDv7.generate()
        let paneUUID = UUIDv7.generate()
        let paneID = PaneId(existingUUID: paneUUID)
        let scrollbarState = ScrollbarState(top: 80, bottom: 100, total: 100)
        let context = TerminalActivityProjectionContext(
            isAttended: false,
            isAgentClassified: true,
            outputBurstThreshold: 4
        )
        let runtime = TerminalRuntime(
            paneId: paneID,
            metadata: PaneMetadata(paneId: paneID, title: "Runtime")
        )
        let runtimeRegistry = RuntimeRegistry()
        _ = runtimeRegistry.register(runtime)
        let recorder = LocalActionDrainRecorder()
        let activityBindingID = UUIDv7.generate()
        let originalRegistry = Ghostty.ActionRouter.runtimeRegistryForActionRouting
        Ghostty.ActionRouter.setRuntimeRegistry(runtimeRegistry)
        Ghostty.ActionRouter.bindTerminalActivityInput(
            id: activityBindingID,
            context: { requestedPaneID in
                #expect(requestedPaneID == paneUUID)
                return context
            },
            sink: { input in recorder.activityInputs.append(input) }
        )
        defer {
            Ghostty.ActionRouter.retireLocalActions(for: surfaceID)
            Ghostty.ActionRouter.unbindTerminalActivityInput(id: activityBindingID)
            Ghostty.ActionRouter.setRuntimeRegistry(originalRegistry)
        }
        let hostAccess = TerminalLocalActionDrainHostAccess { requestedSurfaceID in
            guard requestedSurfaceID == surfaceID else { return nil }
            return TerminalLocalActionDrainMountedHost(
                paneID: paneUUID,
                surfaceView: nil,
                hostScrollbarState: { recorder.hostScrollbarState },
                updateHostScrollbarState: { recorder.hostScrollbarState = $0 }
            )
        }

        #expect(
            Ghostty.ActionRouter.localActionAccumulator.offer(
                .scrollbar(scrollbarState, observedAtMilliseconds: 10),
                for: surfaceID
            ) == .scheduled
        )
        await Ghostty.ActionRouter.drainLocalActions(for: surfaceID, hostAccess: hostAccess)

        #expect(recorder.hostScrollbarState == scrollbarState)
        #expect(runtime.scrollbarState == scrollbarState)
        let input = try #require(recorder.activityInputs.first)
        guard case .aggregate(let submittedSurfaceID, let submittedPaneID, let aggregateInput) = input else {
            Issue.record("expected detached terminal activity aggregate")
            return
        }
        #expect(submittedSurfaceID == surfaceID)
        #expect(submittedPaneID == paneUUID)
        #expect(aggregateInput.latestState == scrollbarState)
        #expect(aggregateInput.context == context)
        #expect(recorder.activityInputs.count == 1)
    }

    @Test("local drain without runtime writes host cache and preserves a newer callback")
    func localDrainWithoutRuntimePreservesHostAndFollowUp() async throws {
        let surfaceID = UUIDv7.generate()
        let paneUUID = UUIDv7.generate()
        let paneID = PaneId(existingUUID: paneUUID)
        let detachedState = ScrollbarState(top: 80, bottom: 100, total: 100)
        let newerState = ScrollbarState(top: 81, bottom: 101, total: 101)
        let recorder = LocalActionDrainRecorder()
        let originalRegistry = Ghostty.ActionRouter.runtimeRegistryForActionRouting
        #expect(RuntimeRegistry.shared.runtime(for: paneID) == nil)
        Ghostty.ActionRouter.setRuntimeRegistry(RuntimeRegistry())
        defer {
            Ghostty.ActionRouter.retireLocalActions(for: surfaceID)
            Ghostty.ActionRouter.setRuntimeRegistry(originalRegistry)
        }
        let hostAccess = TerminalLocalActionDrainHostAccess { requestedSurfaceID in
            guard requestedSurfaceID == surfaceID else { return nil }
            return TerminalLocalActionDrainMountedHost(
                paneID: paneUUID,
                surfaceView: nil,
                hostScrollbarState: { recorder.hostScrollbarState },
                updateHostScrollbarState: { state in
                    recorder.hostScrollbarState = state
                    _ = Ghostty.ActionRouter.localActionAccumulator.offer(
                        .scrollbar(newerState, observedAtMilliseconds: 11),
                        for: surfaceID
                    )
                }
            )
        }

        _ = Ghostty.ActionRouter.localActionAccumulator.offer(
            .scrollbar(detachedState, observedAtMilliseconds: 10),
            for: surfaceID
        )
        await Ghostty.ActionRouter.drainLocalActions(for: surfaceID, hostAccess: hostAccess)
        Ghostty.ActionRouter.localActionDrainScheduler.cancel(for: surfaceID)

        #expect(recorder.hostScrollbarState == detachedState)
        #expect(Ghostty.ActionRouter.localActionAccumulator.hasPendingActions(for: surfaceID))
        let followUp = try #require(Ghostty.ActionRouter.localActionAccumulator.beginDrain(for: surfaceID))
        #expect(followUp.presentation.scrollbarState == newerState)
        #expect(Ghostty.ActionRouter.localActionAccumulator.finishDrain(for: surfaceID) == .idle)
    }

    @Test("local drain without runtime submits detached activity")
    func localDrainWithoutRuntimeSubmitsActivity() async throws {
        let surfaceID = UUIDv7.generate()
        let paneUUID = UUIDv7.generate()
        let paneID = PaneId(existingUUID: paneUUID)
        let scrollbarState = ScrollbarState(top: 80, bottom: 100, total: 100)
        let context = TerminalActivityProjectionContext(
            isAttended: false,
            isAgentClassified: true,
            outputBurstThreshold: 4
        )
        let recorder = LocalActionDrainRecorder()
        let activityBindingID = UUIDv7.generate()
        let originalRegistry = Ghostty.ActionRouter.runtimeRegistryForActionRouting
        #expect(RuntimeRegistry.shared.runtime(for: paneID) == nil)
        Ghostty.ActionRouter.setRuntimeRegistry(RuntimeRegistry())
        Ghostty.ActionRouter.bindTerminalActivityInput(
            id: activityBindingID,
            context: { _ in context },
            sink: { recorder.activityInputs.append($0) }
        )
        defer {
            Ghostty.ActionRouter.retireLocalActions(for: surfaceID)
            Ghostty.ActionRouter.unbindTerminalActivityInput(id: activityBindingID)
            Ghostty.ActionRouter.setRuntimeRegistry(originalRegistry)
        }
        let hostAccess = TerminalLocalActionDrainHostAccess { requestedSurfaceID in
            guard requestedSurfaceID == surfaceID else { return nil }
            return TerminalLocalActionDrainMountedHost(
                paneID: paneUUID,
                surfaceView: nil,
                hostScrollbarState: { recorder.hostScrollbarState },
                updateHostScrollbarState: { recorder.hostScrollbarState = $0 }
            )
        }

        _ = Ghostty.ActionRouter.localActionAccumulator.offer(
            .scrollbar(scrollbarState, observedAtMilliseconds: 10),
            for: surfaceID
        )
        await Ghostty.ActionRouter.drainLocalActions(for: surfaceID, hostAccess: hostAccess)

        let input = try #require(recorder.activityInputs.first)
        guard case .aggregate(let submittedSurfaceID, let submittedPaneID, let aggregateInput) = input else {
            Issue.record("expected detached terminal activity aggregate")
            return
        }
        #expect(submittedSurfaceID == surfaceID)
        #expect(submittedPaneID == paneUUID)
        #expect(aggregateInput.latestState == scrollbarState)
        #expect(aggregateInput.context == context)
        #expect(recorder.activityInputs.count == 1)
    }

    @Test("local drain retires an invalid or replaced mounted lifetime")
    func localDrainRetiresInvalidMountedLifetime() async {
        let surfaceID = UUIDv7.generate()
        defer { Ghostty.ActionRouter.retireLocalActions(for: surfaceID) }
        _ = Ghostty.ActionRouter.localActionAccumulator.offer(
            .scrollbar(ScrollbarState(top: 80, bottom: 100, total: 100), observedAtMilliseconds: 10),
            for: surfaceID
        )

        await Ghostty.ActionRouter.drainLocalActions(
            for: surfaceID,
            hostAccess: TerminalLocalActionDrainHostAccess { _ in nil }
        )

        #expect(!Ghostty.ActionRouter.localActionAccumulator.hasPendingActions(for: surfaceID))
    }
}

@MainActor
private final class LocalActionDrainRecorder {
    var hostScrollbarState: ScrollbarState?
    var activityInputs: [TerminalActivitySourceInput] = []
}
