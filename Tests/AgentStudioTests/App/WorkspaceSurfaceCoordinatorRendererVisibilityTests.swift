import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

@MainActor
@Suite("WorkspaceSurfaceCoordinator renderer visibility", .serialized)
struct WorkspaceSurfaceCoordinatorRendererVisibilityTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("joins exact attached panes with active tab and owning window facts")
    func joinsExactAttachedPanesWithActiveTabAndOwningWindowFacts() async {
        await withAsyncTestCoreAtoms { _ in
            // Arrange
            let store = WorkspaceStore()
            let firstPane = store.createPane()
            let firstTab = Tab(paneId: firstPane.id)
            store.appendTab(firstTab)
            let secondPane = store.createPane()
            let secondTab = Tab(paneId: secondPane.id)
            store.appendTab(secondTab)
            store.setActiveTab(firstTab.id)

            let firstSurfaceID = UUIDv7.generate()
            let secondSurfaceID = UUIDv7.generate()
            let surfaceManager = RendererVisibilityCapturingSurfaceManager(
                bindings: [
                    firstSurfaceID: firstPane.id,
                    secondSurfaceID: secondPane.id,
                ]
            )
            let windowLifecycle = WindowLifecycleAtom()
            let windowID = UUIDv7.generate()
            windowLifecycle.recordWindowRegistered(windowID)
            let coordinator = WorkspaceSurfaceCoordinator(
                store: store,
                viewRegistry: ViewRegistry(),
                runtime: SessionRuntime(store: store),
                surfaceManager: surfaceManager,
                runtimeRegistry: RuntimeRegistry(),
                paneEventBus: EventBus<RuntimeEnvelope>(),
                windowLifecycleStore: windowLifecycle,
                bridgePaneAttendance: BridgePaneAttendanceAtom()
            )

            // Act — missing/hidden window facts dominate the active tab.
            coordinator.bindRendererVisibility(toOwningWindowId: windowID)

            // Assert
            #expect(
                surfaceManager.lastVisibilityBySurfaceID
                    == [firstSurfaceID: false, secondSurfaceID: false]
            )

            // Act — visible window reveals only the active tab.
            windowLifecycle.recordWindowPresentation(
                WindowPresentationFacts(
                    isVisible: true,
                    isMiniaturized: false,
                    isOccluded: false
                ),
                for: windowID
            )
            await eventually("visible window reconciliation") {
                surfaceManager.lastVisibilityBySurfaceID
                    == [firstSurfaceID: true, secondSurfaceID: false]
            }

            // Act — active-tab observation rearms and flips the exact results.
            store.setActiveTab(secondTab.id)
            await eventually("active tab reconciliation") {
                surfaceManager.lastVisibilityBySurfaceID
                    == [firstSurfaceID: false, secondSurfaceID: true]
            }

            // Act — an exact membership change explicitly rearms observation.
            let reconciliationCountBeforeBindingChange = surfaceManager.reconciliationCount
            surfaceManager.replaceBindings([firstSurfaceID: firstPane.id])
            await eventually("attached binding reconciliation") {
                surfaceManager.reconciliationCount == reconciliationCountBeforeBindingChange + 1
            }
            #expect(surfaceManager.lastVisibilityBySurfaceID == [firstSurfaceID: false])

            await coordinator.shutdown()
            let reconciliationCountAfterShutdown = surfaceManager.reconciliationCount
            surfaceManager.replaceBindings([secondSurfaceID: secondPane.id])
            #expect(surfaceManager.reconciliationCount == reconciliationCountAfterShutdown)
        }
    }

    @Test("miniaturization and occlusion independently hide attached panes")
    func miniaturizationAndOcclusionIndependentlyHideAttachedPanes() async {
        await withAsyncTestCoreAtoms { _ in
            // Arrange
            let store = WorkspaceStore()
            let pane = store.createPane()
            store.appendTab(Tab(paneId: pane.id))
            let surfaceID = UUIDv7.generate()
            let surfaceManager = RendererVisibilityCapturingSurfaceManager(
                bindings: [surfaceID: pane.id]
            )
            let windowLifecycle = WindowLifecycleAtom()
            let windowID = UUIDv7.generate()
            windowLifecycle.recordWindowRegistered(windowID)
            let coordinator = WorkspaceSurfaceCoordinator(
                store: store,
                viewRegistry: ViewRegistry(),
                runtime: SessionRuntime(store: store),
                surfaceManager: surfaceManager,
                runtimeRegistry: RuntimeRegistry(),
                paneEventBus: EventBus<RuntimeEnvelope>(),
                windowLifecycleStore: windowLifecycle,
                bridgePaneAttendance: BridgePaneAttendanceAtom()
            )
            coordinator.bindRendererVisibility(toOwningWindowId: windowID)

            // Act and assert — visible.
            windowLifecycle.recordWindowPresentation(
                WindowPresentationFacts(isVisible: true, isMiniaturized: false, isOccluded: false),
                for: windowID
            )
            await eventually("visible renderer") {
                surfaceManager.lastVisibilityBySurfaceID == [surfaceID: true]
            }

            // Act and assert — miniaturized.
            windowLifecycle.recordWindowPresentation(
                WindowPresentationFacts(isVisible: true, isMiniaturized: true, isOccluded: false),
                for: windowID
            )
            await eventually("miniaturized renderer") {
                surfaceManager.lastVisibilityBySurfaceID == [surfaceID: false]
            }

            // Act and assert — occluded.
            windowLifecycle.recordWindowPresentation(
                WindowPresentationFacts(isVisible: true, isMiniaturized: false, isOccluded: true),
                for: windowID
            )
            await eventually("occluded renderer") {
                surfaceManager.lastVisibilityBySurfaceID == [surfaceID: false]
            }

            await coordinator.shutdown()
        }
    }

    @Test("switching arrangements observes the active minimized-pane set")
    func switchingArrangementsObservesActiveMinimizedPaneSet() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let store = WorkspaceStore()
            let firstPane = store.createPane()
            let secondPane = store.createPane()
            let tab = Tab(paneId: firstPane.id)
            store.appendTab(tab)
            #expect(
                store.insertPane(
                    secondPane.id,
                    inTab: tab.id,
                    at: firstPane.id,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                ))
            let defaultArrangementID = tab.activeArrangementId
            let alternateArrangementID = try #require(
                store.createArrangement(name: "Alternate", inTab: tab.id)
            )
            #expect(store.minimizePane(firstPane.id, inTab: tab.id))
            store.switchArrangement(to: defaultArrangementID, inTab: tab.id)

            let surfaceID = UUIDv7.generate()
            let surfaceManager = RendererVisibilityCapturingSurfaceManager(
                bindings: [surfaceID: firstPane.id]
            )
            let windowLifecycle = WindowLifecycleAtom()
            let windowID = UUIDv7.generate()
            windowLifecycle.recordWindowRegistered(windowID)
            windowLifecycle.recordWindowPresentation(
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
                windowLifecycleStore: windowLifecycle,
                bridgePaneAttendance: BridgePaneAttendanceAtom()
            )
            coordinator.bindRendererVisibility(toOwningWindowId: windowID)
            #expect(surfaceManager.lastVisibilityBySurfaceID == [surfaceID: true])

            store.switchArrangement(to: alternateArrangementID, inTab: tab.id)
            await eventually("alternate arrangement hides minimized renderer") {
                surfaceManager.lastVisibilityBySurfaceID == [surfaceID: false]
            }

            store.switchArrangement(to: defaultArrangementID, inTab: tab.id)
            await eventually("default arrangement reveals renderer") {
                surfaceManager.lastVisibilityBySurfaceID == [surfaceID: true]
            }

            await coordinator.shutdown()
        }
    }

    @Test("minimizing a drawer parent hides both parent and drawer-child renderers")
    func minimizingDrawerParentHidesParentAndDrawerChildRenderers() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let store = WorkspaceStore()
            let parentPane = store.createPane()
            let siblingPane = store.createPane()
            let tab = Tab(paneId: parentPane.id)
            store.appendTab(tab)
            #expect(
                store.insertPane(
                    siblingPane.id,
                    inTab: tab.id,
                    at: parentPane.id,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                ))
            let drawerPane = try #require(store.addDrawerPane(to: parentPane.id))

            let parentSurfaceID = UUIDv7.generate()
            let drawerSurfaceID = UUIDv7.generate()
            let surfaceManager = RendererVisibilityCapturingSurfaceManager(
                bindings: [
                    parentSurfaceID: parentPane.id,
                    drawerSurfaceID: drawerPane.id,
                ]
            )
            let windowLifecycle = WindowLifecycleAtom()
            let windowID = UUIDv7.generate()
            windowLifecycle.recordWindowRegistered(windowID)
            windowLifecycle.recordWindowPresentation(
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
                windowLifecycleStore: windowLifecycle,
                bridgePaneAttendance: BridgePaneAttendanceAtom()
            )
            coordinator.bindRendererVisibility(toOwningWindowId: windowID)
            #expect(
                surfaceManager.lastVisibilityBySurfaceID
                    == [parentSurfaceID: true, drawerSurfaceID: true]
            )

            #expect(store.minimizePane(parentPane.id, inTab: tab.id))
            await eventually("minimized drawer parent hides its renderer cohort") {
                surfaceManager.lastVisibilityBySurfaceID
                    == [parentSurfaceID: false, drawerSurfaceID: false]
            }

            store.expandPane(parentPane.id, inTab: tab.id)
            await eventually("expanded drawer parent reveals its renderer cohort") {
                surfaceManager.lastVisibilityBySurfaceID
                    == [parentSurfaceID: true, drawerSurfaceID: true]
            }

            await coordinator.shutdown()
        }
    }

    @Test("delivery validation rejects missed, wrong, and redundant surface delivery")
    func deliveryValidationRejectsIncorrectSurfaceResults() {
        let firstPaneID = UUIDv7.generate()
        let secondPaneID = UUIDv7.generate()
        let before = [firstPaneID: true, secondPaneID: false]
        let desired = [firstPaneID: false, secondPaneID: true]

        #expect(
            RendererLifecycleDeliveryValidation.isExact(
                before: before,
                after: desired,
                desired: desired,
                visibilityDeliveryDelta: 2,
                projectionChangedSurfaceDelta: 2
            ))
        #expect(
            !RendererLifecycleDeliveryValidation.isExact(
                before: before,
                after: [firstPaneID: true, secondPaneID: true],
                desired: desired,
                visibilityDeliveryDelta: 1,
                projectionChangedSurfaceDelta: 1
            ))
        #expect(
            !RendererLifecycleDeliveryValidation.isExact(
                before: before,
                after: [firstPaneID: true, secondPaneID: false],
                desired: desired,
                visibilityDeliveryDelta: 2,
                projectionChangedSurfaceDelta: 2
            ))
        #expect(
            !RendererLifecycleDeliveryValidation.isExact(
                before: before,
                after: desired,
                desired: desired,
                visibilityDeliveryDelta: 3,
                projectionChangedSurfaceDelta: 3
            ))
    }
}

@MainActor
private final class RendererVisibilityCapturingSurfaceManager: WorkspaceSurfaceManaging {
    private var bindings: [UUID: UUID]
    private var bindingsChangeHandler: (() -> Void)?
    private(set) var reconciliations: [[UUID: Bool]] = []

    init(bindings: [UUID: UUID]) {
        self.bindings = bindings
    }

    var reconciliationCount: Int {
        reconciliations.count
    }

    var lastVisibilityBySurfaceID: [UUID: Bool]? {
        reconciliations.last
    }

    func replaceBindings(_ bindings: [UUID: UUID]) {
        self.bindings = bindings
        bindingsChangeHandler?()
    }

    func setAttachedBindingsChangeHandler(_ handler: (() -> Void)?) {
        bindingsChangeHandler = handler
    }

    func reconcileAttachedVisibility(
        _ visibilityForPaneID: (UUID) -> Bool
    ) -> SurfaceVisibilityReconciliationResult {
        let visibilityBySurfaceID = bindings.mapValues(visibilityForPaneID)
        reconciliations.append(visibilityBySurfaceID)
        return SurfaceVisibilityReconciliationResult(
            applied: visibilityBySurfaceID.count,
            equal: 0,
            missing: 0,
            failed: 0
        )
    }

    func syncFocus(activeSurfaceId _: UUID?) {}

    func createSurface(
        config _: Ghostty.SurfaceConfiguration,
        metadata _: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        .failure(.ghosttyNotInitialized)
    }

    func attach(_: UUID, to _: UUID) -> Ghostty.SurfaceView? { nil }
    func detach(_: UUID, reason _: SurfaceDetachReason) {}
    func undoClose() -> ManagedSurface? { nil }
    func requeueUndo(_: UUID) {}
    func destroy(_: UUID) {}
}
