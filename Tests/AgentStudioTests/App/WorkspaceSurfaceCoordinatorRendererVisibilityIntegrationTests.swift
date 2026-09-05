import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

/// Renderer-visibility reconciliation against the real `SurfaceManager`, gating the mock-based
/// join proved by `WorkspaceSurfaceCoordinatorRendererVisibilityTests` against production
/// attach/detach/reconcile behavior. `RecordingSurfaceRendererStateDelivery` and
/// `NoOpAppCommandDispatcher` are copied from
/// `SurfaceManagerRendererStateDeliveryTests` because that file lives in the
/// `AgentStudioTerminalTests` target, which this target cannot import.
@MainActor
@Suite("WorkspaceSurfaceCoordinator renderer visibility integration", .serialized)
struct SurfaceRendererVisibilityIntegrationTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    // MARK: - Helpers

    private func makeManager(delivery: RecordingSurfaceRendererStateDelivery) -> SurfaceManager {
        SurfaceManager(
            undoTTL: 300,
            maxCreationRetries: 0,
            healthCheckInterval: 3600,
            delayScheduler: AsyncDelay { _ in },
            rendererStateDelivery: delivery
        )
    }

    private func makeBareSurface() -> Ghostty.SurfaceView {
        Ghostty.SurfaceView(
            managedSurfaceID: UUIDv7.generate(),
            appCommandDispatcher: NoOpAppCommandDispatcher()
        )
    }

    private func acceptedSurface(
        _ surface: Ghostty.SurfaceView,
        in manager: SurfaceManager
    ) throws -> ManagedSurface {
        try manager.acceptCreatedSurface(
            surface,
            metadata: SurfaceMetadata(paneId: UUIDv7.generate())
        ).get()
    }

    // MARK: - Tests

    @Test("tab switch delivers exactly the changed surfaces")
    func tabSwitchDeliversExactlyTheChangedSurfaces() async throws {
        try await withAsyncTestCoreAtoms { _ in
            // Arrange
            let store = WorkspaceStore()
            let paneOne = store.createPane()
            let tabOne = Tab(paneId: paneOne.id)
            store.appendTab(tabOne)
            let paneTwo = store.createPane()
            let tabTwo = Tab(paneId: paneTwo.id)
            store.appendTab(tabTwo)
            store.setActiveTab(tabOne.id)

            let delivery = RecordingSurfaceRendererStateDelivery()
            let surfaceManager = makeManager(delivery: delivery)
            let surfaceOne = try acceptedSurface(makeBareSurface(), in: surfaceManager)
            let surfaceTwo = try acceptedSurface(makeBareSurface(), in: surfaceManager)
            delivery.reset()
            surfaceManager.attach(surfaceOne.id, to: paneOne.id)
            surfaceManager.attach(surfaceTwo.id, to: paneTwo.id)

            let windowLifecycleStore = WindowLifecycleAtom()
            let windowID = UUIDv7.generate()
            windowLifecycleStore.recordWindowRegistered(windowID)
            windowLifecycleStore.recordWindowPresentation(
                WindowPresentationFacts(isVisible: true, isMiniaturized: false, isOccluded: false),
                for: windowID
            )
            let coordinator = WorkspaceSurfaceCoordinator(
                store: store,
                viewRegistry: ViewRegistry(),
                runtime: SessionRuntime(store: store),
                surfaceManager: surfaceManager,
                runtimeRegistry: RuntimeRegistry(),
                paneEventBus: EventBus<RuntimeEnvelope>(),
                windowLifecycleStore: windowLifecycleStore,
                bridgePaneAttendance: BridgePaneAttendanceAtom()
            )

            // Act — bind while tab one is active.
            coordinator.bindRendererVisibility(toOwningWindowId: windowID)

            // Assert — attach delivered `true` for both surfaces; the initial reconciliation then
            // hides the inactive tab's surface and leaves the active tab's surface untouched
            // (its delivered value already equals the desired value).
            #expect(
                delivery.visibilityCalls.filter { $0.surfaceID == surfaceTwo.id }
                    == [
                        .init(surfaceID: surfaceTwo.id, visible: true),
                        .init(surfaceID: surfaceTwo.id, visible: false),
                    ]
            )
            #expect(
                delivery.visibilityCalls.filter { $0.surfaceID == surfaceOne.id }
                    == [.init(surfaceID: surfaceOne.id, visible: true)]
            )

            delivery.reset()

            // Act — switch the active tab.
            store.setActiveTab(tabTwo.id)

            // Assert — exactly the two changed surfaces re-deliver, in either dictionary order.
            await eventually("tab switch delivers exactly the two changed surfaces") {
                delivery.visibilityCalls.count == 2
            }
            let deliveredBySurfaceID = Dictionary(
                uniqueKeysWithValues: delivery.visibilityCalls.map { ($0.surfaceID, $0.visible) }
            )
            #expect(deliveredBySurfaceID == [surfaceOne.id: false, surfaceTwo.id: true])
            #expect(delivery.focusCalls == [.init(surfaceID: surfaceOne.id, focused: false)])

            await coordinator.shutdown()
        }
    }

    @Test("a manager-local re-attach that changes no visibility delivers nothing further")
    func managerLocalRewritesDoNotReArmReconciliation() async throws {
        try await withAsyncTestCoreAtoms { _ in
            // Arrange
            let store = WorkspaceStore()
            let pane = store.createPane()
            store.appendTab(Tab(paneId: pane.id))

            let delivery = RecordingSurfaceRendererStateDelivery()
            let surfaceManager = makeManager(delivery: delivery)
            let surface = try acceptedSurface(makeBareSurface(), in: surfaceManager)
            surfaceManager.attach(surface.id, to: pane.id)

            let windowLifecycleStore = WindowLifecycleAtom()
            let windowID = UUIDv7.generate()
            windowLifecycleStore.recordWindowRegistered(windowID)
            windowLifecycleStore.recordWindowPresentation(
                WindowPresentationFacts(isVisible: true, isMiniaturized: false, isOccluded: false),
                for: windowID
            )
            let coordinator = WorkspaceSurfaceCoordinator(
                store: store,
                viewRegistry: ViewRegistry(),
                runtime: SessionRuntime(store: store),
                surfaceManager: surfaceManager,
                runtimeRegistry: RuntimeRegistry(),
                paneEventBus: EventBus<RuntimeEnvelope>(),
                windowLifecycleStore: windowLifecycleStore,
                bridgePaneAttendance: BridgePaneAttendanceAtom()
            )
            coordinator.bindRendererVisibility(toOwningWindowId: windowID)
            delivery.reset()

            // Act — a manager-local rewrite that fires the bindings-changed handler (re-attaching
            // to the same pane, `SurfaceManager`'s "already active" path) without changing any
            // pane's desired visibility. `SurfaceManager` has no exposed reconciliation counter
            // before S7's recorder lands, so the only production-observable proof available here
            // is that the re-triggered reconciliation delivers nothing further, not a literal
            // reconciliation count.
            surfaceManager.attach(surface.id, to: pane.id)
            await Task.yield()

            // Assert
            #expect(delivery.visibilityCalls.isEmpty)
            #expect(delivery.focusCalls.isEmpty)

            // Act — an idle loop with no atom write at all.
            for _ in 0..<50 {
                await Task.yield()
            }

            // Assert — no atom write means zero further deliveries.
            #expect(delivery.visibilityCalls.isEmpty)
            #expect(delivery.focusCalls.isEmpty)

            await coordinator.shutdown()
        }
    }
}

// MARK: - Test Doubles (copied from SurfaceManagerRendererStateDeliveryTests;
// AgentStudioTerminalTests is a separate SwiftPM target and cannot be imported here)

@MainActor
private final class RecordingSurfaceRendererStateDelivery: SurfaceRendererStateDelivery {
    struct VisibilityCall: Equatable {
        let surfaceID: UUID
        let visible: Bool
    }
    struct FocusCall: Equatable {
        let surfaceID: UUID
        let focused: Bool
    }
    var visibilityCalls: [VisibilityCall] = []
    var focusCalls: [FocusCall] = []
    var onVisibilityDelivery: ((Ghostty.SurfaceView, Bool) -> Void)?

    func deliverVisibility(_ visible: Bool, to surface: Ghostty.SurfaceView) -> Bool {
        onVisibilityDelivery?(surface, visible)
        visibilityCalls.append(.init(surfaceID: surface.managedSurfaceID, visible: visible))
        return true
    }

    func deliverFocus(_ focused: Bool, to surface: Ghostty.SurfaceView) -> Bool {
        focusCalls.append(.init(surfaceID: surface.managedSurfaceID, focused: focused))
        return true
    }

    func reset() {
        visibilityCalls.removeAll()
        focusCalls.removeAll()
    }
}

@MainActor
private final class NoOpAppCommandDispatcher: AppCommandDispatching {
    func dispatch(_: AppCommand) {}
    func dispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) {}
    func canDispatch(_: AppCommand) -> Bool { false }
    func canDispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool { false }
    func bridgePaneCommandTarget(worktreeId _: UUID) -> BridgePaneCommandTarget? { nil }
    func dispatchMovePaneToTab(sourcePaneId _: UUID, sourceTabId _: UUID?, targetTabId _: UUID) {}
}
