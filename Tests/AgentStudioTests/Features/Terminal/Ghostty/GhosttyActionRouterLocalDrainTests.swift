import Foundation
import Testing

@testable import AgentStudio

@MainActor
private final class FakeTerminalLocalActionDrainHost: TerminalLocalActionDrainHost {
    let managedSurfaceID: UUID
    private(set) var hostScrollbarState: ScrollbarState?
    private(set) var title = ""
    var performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    var onScrollbarStateChanged: (@MainActor (ScrollbarState) -> Void)?

    init(managedSurfaceID: UUID) {
        self.managedSurfaceID = managedSurfaceID
    }

    func updateHostScrollbarState(_ state: ScrollbarState) {
        hostScrollbarState = state
        onScrollbarStateChanged?(state)
    }

    func titleDidChange(_ title: String) {
        self.title = title
    }
}

@MainActor
private final class TerminalActivityInputRecorder {
    private(set) var inputs: [TerminalActivitySourceInput] = []

    func record(_ input: TerminalActivitySourceInput) {
        inputs.append(input)
    }
}

extension GhosttyActionRouterTests {
    private func offerScrollbarState(
        _ state: ScrollbarState,
        surfaceID: UUID
    ) {
        #expect(
            Ghostty.ActionRouter.admitTranslatedActionToTerminalRuntime(
                .scrollbarChanged(state),
                surfaceID: surfaceID,
                accumulator: Ghostty.ActionRouter.localActionAccumulator
            ) == .handledLocally
        )
        Ghostty.ActionRouter.localActionDrainScheduler.cancel(for: surfaceID)
    }

    private func assertInvalidMountedLifetimeRetiresPendingActions(
        surfaceID: UUID,
        mountedHostResolver: TerminalLocalActionMountedHostResolver
    ) async {
        offerScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 200),
            surfaceID: surfaceID
        )

        await Ghostty.ActionRouter.drainLocalActions(
            for: surfaceID,
            mountedHostResolver: mountedHostResolver
        )

        Ghostty.ActionRouter.localActionDrainScheduler.cancel(for: surfaceID)
        #expect(!Ghostty.ActionRouter.localActionAccumulator.hasPendingActions(for: surfaceID))
    }

    @Test("runtime-present drain preserves host runtime and activity delivery")
    func runtimePresentDrainPreservesExistingDelivery() async throws {
        let surfaceID = UUIDv7.generate()
        let paneUUID = UUIDv7.generate()
        let paneID = PaneId(existingUUID: paneUUID)
        let scrollbarState = ScrollbarState(top: 80, bottom: 120, total: 200)
        let projectionContext = TerminalActivityProjectionContext(
            isAttended: false,
            isAgentClassified: true,
            outputBurstThreshold: 10
        )
        let host = FakeTerminalLocalActionDrainHost(managedSurfaceID: surfaceID)
        let mountedHostResolver = TerminalLocalActionMountedHostResolver(
            surfaceForID: { requestedID in
                requestedID == surfaceID ? host : nil
            },
            paneIDForSurfaceID: { requestedID in
                requestedID == surfaceID ? paneUUID : nil
            }
        )
        let runtime = TerminalRuntime(
            paneId: paneID,
            metadata: PaneMetadata(paneId: paneID, title: "Local drain")
        )
        let runtimeRegistry = RuntimeRegistry()
        _ = runtimeRegistry.register(runtime)
        let activityRecorder = TerminalActivityInputRecorder()
        let activityBindingID = UUIDv7.generate()
        let originalRegistry = Ghostty.ActionRouter.runtimeRegistryForActionRouting

        #expect(RuntimeRegistry.shared.runtime(for: paneID) == nil)
        Ghostty.ActionRouter.setRuntimeRegistry(runtimeRegistry)
        Ghostty.ActionRouter.bindTerminalActivityInput(
            id: activityBindingID,
            context: { requestedPaneID in
                #expect(requestedPaneID == paneUUID)
                return projectionContext
            },
            sink: { input in
                activityRecorder.record(input)
            }
        )
        defer {
            Ghostty.ActionRouter.localActionDrainScheduler.cancel(for: surfaceID)
            Ghostty.ActionRouter.localActionAccumulator.removeSurface(surfaceID)
            Ghostty.ActionRouter.unbindTerminalActivityInput(id: activityBindingID)
            Ghostty.ActionRouter.setRuntimeRegistry(originalRegistry)
        }

        #expect(
            Ghostty.ActionRouter.admitTranslatedActionToTerminalRuntime(
                .scrollbarChanged(scrollbarState),
                surfaceID: surfaceID,
                accumulator: Ghostty.ActionRouter.localActionAccumulator
            ) == .handledLocally
        )
        Ghostty.ActionRouter.localActionDrainScheduler.cancel(for: surfaceID)

        await Ghostty.ActionRouter.drainLocalActions(
            for: surfaceID,
            mountedHostResolver: mountedHostResolver
        )

        #expect(host.hostScrollbarState == scrollbarState)
        #expect(runtime.scrollbarState == scrollbarState)
        let input = try #require(activityRecorder.inputs.first)
        guard
            case .aggregate(
                let recordedSurfaceID,
                let recordedPaneID,
                let aggregateInput
            ) = input
        else {
            Issue.record("Expected one terminal activity aggregate")
            return
        }
        #expect(recordedSurfaceID == surfaceID)
        #expect(recordedPaneID == paneUUID)
        #expect(aggregateInput.latestState == scrollbarState)
        #expect(aggregateInput.context == projectionContext)
        #expect(aggregateInput.aggregate.sampleCount == 1)
    }

    @Test("no-runtime drain delivers host state and preserves a callback offered during delivery")
    func noRuntimeDrainDeliversHostStateAndFollowUp() async {
        let surfaceID = UUIDv7.generate()
        let paneUUID = UUIDv7.generate()
        let paneID = PaneId(existingUUID: paneUUID)
        let initialState = ScrollbarState(top: 80, bottom: 120, total: 200)
        let followUpState = ScrollbarState(top: 90, bottom: 130, total: 210)
        let host = FakeTerminalLocalActionDrainHost(managedSurfaceID: surfaceID)
        let mountedHostResolver = TerminalLocalActionMountedHostResolver(
            surfaceForID: { requestedID in
                requestedID == surfaceID ? host : nil
            },
            paneIDForSurfaceID: { requestedID in
                requestedID == surfaceID ? paneUUID : nil
            }
        )
        let originalRegistry = Ghostty.ActionRouter.runtimeRegistryForActionRouting
        Ghostty.ActionRouter.setRuntimeRegistry(RuntimeRegistry())
        defer {
            Ghostty.ActionRouter.localActionDrainScheduler.cancel(for: surfaceID)
            Ghostty.ActionRouter.localActionAccumulator.removeSurface(surfaceID)
            Ghostty.ActionRouter.setRuntimeRegistry(originalRegistry)
        }
        #expect(RuntimeRegistry.shared.runtime(for: paneID) == nil)

        var didOfferFollowUp = false
        host.onScrollbarStateChanged = { _ in
            guard !didOfferFollowUp else { return }
            didOfferFollowUp = true
            _ = Ghostty.ActionRouter.admitTranslatedActionToTerminalRuntime(
                .scrollbarChanged(followUpState),
                surfaceID: surfaceID,
                accumulator: Ghostty.ActionRouter.localActionAccumulator
            )
        }
        offerScrollbarState(initialState, surfaceID: surfaceID)

        await Ghostty.ActionRouter.drainLocalActions(
            for: surfaceID,
            mountedHostResolver: mountedHostResolver
        )
        Ghostty.ActionRouter.localActionDrainScheduler.cancel(for: surfaceID)

        #expect(host.hostScrollbarState == initialState)
        #expect(Ghostty.ActionRouter.localActionAccumulator.hasPendingActions(for: surfaceID))

        await Ghostty.ActionRouter.drainLocalActions(
            for: surfaceID,
            mountedHostResolver: mountedHostResolver
        )
        Ghostty.ActionRouter.localActionDrainScheduler.cancel(for: surfaceID)

        #expect(host.hostScrollbarState == followUpState)
        #expect(!Ghostty.ActionRouter.localActionAccumulator.hasPendingActions(for: surfaceID))
    }

    @Test("no-runtime drain submits detached activity and records compact performance")
    func noRuntimeDrainSubmitsActivityAndRecordsPerformance() async throws {
        let surfaceID = UUIDv7.generate()
        let paneUUID = UUIDv7.generate()
        let paneID = PaneId(existingUUID: paneUUID)
        let scrollbarState = ScrollbarState(top: 80, bottom: 120, total: 200)
        let projectionContext = TerminalActivityProjectionContext(
            isAttended: false,
            isAgentClassified: true,
            outputBurstThreshold: 10
        )
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_NAME": "no-runtime-local-drain",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 932,
            timeUnixNano: { 123 }
        )
        let performanceRecorder = AgentStudioPerformanceTraceRecorder(traceRuntime: traceRuntime)
        let host = FakeTerminalLocalActionDrainHost(managedSurfaceID: surfaceID)
        host.performanceTraceRecorder = performanceRecorder
        let mountedHostResolver = TerminalLocalActionMountedHostResolver(
            surfaceForID: { requestedID in
                requestedID == surfaceID ? host : nil
            },
            paneIDForSurfaceID: { requestedID in
                requestedID == surfaceID ? paneUUID : nil
            }
        )
        let activityRecorder = TerminalActivityInputRecorder()
        let activityBindingID = UUIDv7.generate()
        let originalRegistry = Ghostty.ActionRouter.runtimeRegistryForActionRouting
        Ghostty.ActionRouter.setRuntimeRegistry(RuntimeRegistry())
        Ghostty.ActionRouter.bindTerminalActivityInput(
            id: activityBindingID,
            context: { requestedPaneID in
                #expect(requestedPaneID == paneUUID)
                return projectionContext
            },
            sink: { input in
                activityRecorder.record(input)
            }
        )
        defer {
            Ghostty.ActionRouter.localActionDrainScheduler.cancel(for: surfaceID)
            Ghostty.ActionRouter.localActionAccumulator.removeSurface(surfaceID)
            Ghostty.ActionRouter.unbindTerminalActivityInput(id: activityBindingID)
            Ghostty.ActionRouter.setRuntimeRegistry(originalRegistry)
        }
        #expect(RuntimeRegistry.shared.runtime(for: paneID) == nil)
        offerScrollbarState(scrollbarState, surfaceID: surfaceID)

        await Ghostty.ActionRouter.drainLocalActions(
            for: surfaceID,
            mountedHostResolver: mountedHostResolver
        )
        Ghostty.ActionRouter.localActionDrainScheduler.cancel(for: surfaceID)
        try await performanceRecorder.drain()

        #expect(host.hostScrollbarState == scrollbarState)
        let input = try #require(activityRecorder.inputs.first)
        guard case .aggregate(let recordedSurfaceID, let recordedPaneID, let aggregateInput) = input else {
            Issue.record("Expected one terminal activity aggregate")
            return
        }
        #expect(recordedSurfaceID == surfaceID)
        #expect(recordedPaneID == paneUUID)
        #expect(aggregateInput.latestState == scrollbarState)
        #expect(aggregateInput.context == projectionContext)

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"performance.terminal.compact_apply\""))
        #expect(contents.contains("\"body\":\"performance.terminal.accumulator_drain\""))
        #expect(contents.contains("\"agentstudio.performance.terminal.equal_write_suppressed.count\":0"))
        #expect(contents.contains("\"agentstudio.performance.terminal.accumulator.mainactor_task.count\":1"))
    }

    @Test("missing mounted surface retires pending local actions")
    func missingMountedSurfaceRetiresPendingLocalActions() async {
        let surfaceID = UUIDv7.generate()
        defer {
            Ghostty.ActionRouter.localActionDrainScheduler.cancel(for: surfaceID)
            Ghostty.ActionRouter.localActionAccumulator.removeSurface(surfaceID)
        }

        await assertInvalidMountedLifetimeRetiresPendingActions(
            surfaceID: surfaceID,
            mountedHostResolver: TerminalLocalActionMountedHostResolver(
                surfaceForID: { _ in nil },
                paneIDForSurfaceID: { _ in UUIDv7.generate() }
            )
        )
    }

    @Test("replacement mounted surface retires pending local actions")
    func replacementMountedSurfaceRetiresPendingLocalActions() async {
        let surfaceID = UUIDv7.generate()
        let replacementHost = FakeTerminalLocalActionDrainHost(managedSurfaceID: UUIDv7.generate())
        defer {
            Ghostty.ActionRouter.localActionDrainScheduler.cancel(for: surfaceID)
            Ghostty.ActionRouter.localActionAccumulator.removeSurface(surfaceID)
        }

        await assertInvalidMountedLifetimeRetiresPendingActions(
            surfaceID: surfaceID,
            mountedHostResolver: TerminalLocalActionMountedHostResolver(
                surfaceForID: { _ in replacementHost },
                paneIDForSurfaceID: { _ in UUIDv7.generate() }
            )
        )
    }

    @Test("missing pane mapping retires pending local actions")
    func missingPaneMappingRetiresPendingLocalActions() async {
        let surfaceID = UUIDv7.generate()
        let host = FakeTerminalLocalActionDrainHost(managedSurfaceID: surfaceID)
        defer {
            Ghostty.ActionRouter.localActionDrainScheduler.cancel(for: surfaceID)
            Ghostty.ActionRouter.localActionAccumulator.removeSurface(surfaceID)
        }

        await assertInvalidMountedLifetimeRetiresPendingActions(
            surfaceID: surfaceID,
            mountedHostResolver: TerminalLocalActionMountedHostResolver(
                surfaceForID: { _ in host },
                paneIDForSurfaceID: { _ in nil }
            )
        )
    }

    private func temporaryTraceDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-local-action-drain-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
