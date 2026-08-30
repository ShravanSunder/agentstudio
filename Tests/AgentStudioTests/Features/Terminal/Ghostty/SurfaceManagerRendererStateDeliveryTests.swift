import AgentStudioCore
import AgentStudioInfrastructure
import AppKit
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudioTerminal

@MainActor
@Suite("SurfaceManagerRendererStateDeliveryTests", .serialized)
struct SurfaceManagerRendererStateDeliveryTests {
    @Test("accepting a created surface delivers hidden before manager ownership")
    func acceptingCreatedSurfaceDeliversHiddenBeforeManagerOwnership() throws {
        let delivery = RecordingSurfaceRendererStateDelivery()
        let manager = makeManager(delivery: delivery)
        var managerOwnedWhenDelivered: Bool?
        delivery.onVisibilityDelivery = { surface, _ in
            managerOwnedWhenDelivered = manager.managedSurface(for: surface.managedSurfaceID) != nil
        }
        let surface = makeBareSurface()

        let managed = try acceptedSurface(surface, in: manager)

        #expect(delivery.visibilityCalls == [.init(surfaceID: managed.id, visible: false)])
        #expect(managerOwnedWhenDelivered == false)
        #expect(managed.lastDeliveredVisibility == false)
        #expect(manager.hiddenSurfaceCount == 1)
    }

    @Test("attach stays paused until projection reconciliation and suppresses equal delivery")
    func attachStaysPausedUntilProjectionReconciliation() throws {
        let delivery = RecordingSurfaceRendererStateDelivery()
        let manager = makeManager(delivery: delivery)
        let managed = try acceptedSurface(makeBareSurface(), in: manager)
        delivery.reset()

        let attached = manager.attach(managed.id, to: UUIDv7.generate())
        let firstResult = manager.reconcileAttachedVisibility([managed.id: true])
        let equalResult = manager.reconcileAttachedVisibility([managed.id: true])

        #expect(attached === managed.surface)
        #expect(delivery.visibilityCalls == [.init(surfaceID: managed.id, visible: true)])
        #expect(firstResult.applied == 1)
        #expect(firstResult.equal == 0)
        #expect(equalResult.applied == 0)
        #expect(equalResult.equal == 1)
    }

    @Test("detach delivers hidden while the exact surface is still attached")
    func detachDeliversHiddenBeforeRemovingAttachment() throws {
        let delivery = RecordingSurfaceRendererStateDelivery()
        let manager = makeManager(delivery: delivery)
        let managed = try acceptedSurface(makeBareSurface(), in: manager)
        _ = manager.attach(managed.id, to: UUIDv7.generate())
        _ = manager.reconcileAttachedVisibility([managed.id: true])
        delivery.reset()
        var wasAttachedDuringHiddenDelivery = false
        delivery.onVisibilityDelivery = { _, visible in
            if !visible {
                wasAttachedDuringHiddenDelivery = manager.activeSurfaceIds.contains(managed.id)
            }
        }

        manager.detach(managed.id, reason: .hide)

        #expect(wasAttachedDuringHiddenDelivery)
        #expect(delivery.visibilityCalls == [.init(surfaceID: managed.id, visible: false)])
        #expect(manager.activeSurfaceCount == 0)
        #expect(manager.hiddenSurfaceCount == 1)
    }

    @Test("reattach preserves the delivered hidden cache and can reveal again")
    func reattachCanRevealAfterDetach() throws {
        let delivery = RecordingSurfaceRendererStateDelivery()
        let manager = makeManager(delivery: delivery)
        let managed = try acceptedSurface(makeBareSurface(), in: manager)
        let paneID = UUIDv7.generate()
        _ = manager.attach(managed.id, to: paneID)
        _ = manager.reconcileAttachedVisibility([managed.id: true])
        delivery.reset()

        manager.detach(managed.id, reason: .hide)
        _ = manager.attach(managed.id, to: paneID)
        let revealResult = manager.reconcileAttachedVisibility([managed.id: true])

        #expect(
            delivery.visibilityCalls == [
                .init(surfaceID: managed.id, visible: false),
                .init(surfaceID: managed.id, visible: true),
            ])
        #expect(revealResult.applied == 1)
        #expect(revealResult.equal == 0)
        #expect(manager.managedSurface(for: managed.id)?.lastDeliveredVisibility == true)
    }

    @Test("pane visibility closure receives only exact attached pane bindings")
    func paneVisibilityClosureReceivesExactAttachedPaneBindings() throws {
        let delivery = RecordingSurfaceRendererStateDelivery()
        let manager = makeManager(delivery: delivery)
        let managed = try acceptedSurface(makeBareSurface(), in: manager)
        let paneID = UUIDv7.generate()
        _ = manager.attach(managed.id, to: paneID)
        delivery.reset()
        var receivedPaneIDs: [UUID] = []

        let result = manager.reconcileAttachedVisibility { receivedPaneID in
            receivedPaneIDs.append(receivedPaneID)
            return true
        }

        #expect(receivedPaneIDs == [paneID])
        #expect(result.applied == 1)
        #expect(delivery.visibilityCalls == [.init(surfaceID: managed.id, visible: true)])
    }

    @Test("attached binding callback fires for identity changes but not renderer state changes")
    func attachedBindingCallbackTracksBindingIdentityOnly() throws {
        let delivery = RecordingSurfaceRendererStateDelivery()
        let manager = makeManager(delivery: delivery)
        let managed = try acceptedSurface(makeBareSurface(), in: manager)
        var snapshots: [[UUID: UUID]] = []
        manager.onAttachedBindingsChanged = { snapshots.append($0) }
        let firstPaneID = UUIDv7.generate()
        let secondPaneID = UUIDv7.generate()

        _ = manager.attach(managed.id, to: firstPaneID)
        _ = manager.reconcileAttachedVisibility([managed.id: true])
        manager.move(managed.id, to: secondPaneID)

        #expect(
            snapshots == [
                [managed.id: firstPaneID],
                [managed.id: secondPaneID],
            ])
    }

    @Test("focus true is admitted only by the creating manager for an attached visible view")
    func focusTrueRequiresExactVisibleManagerOwnership() throws {
        let firstDelivery = RecordingSurfaceRendererStateDelivery()
        let secondDelivery = RecordingSurfaceRendererStateDelivery()
        let firstManager = makeManager(delivery: firstDelivery)
        let secondManager = makeManager(delivery: secondDelivery)
        let firstSurface = makeBareSurface()
        let secondSurface = makeBareSurface()
        let firstManaged = try acceptedSurface(firstSurface, in: firstManager)
        let secondManaged = try acceptedSurface(secondSurface, in: secondManager)
        _ = firstManager.attach(firstManaged.id, to: UUIDv7.generate())
        _ = secondManager.attach(secondManaged.id, to: UUIDv7.generate())
        firstDelivery.reset()
        secondDelivery.reset()

        #expect(firstSurface.requestManagedFocus(true) == false)
        _ = firstManager.reconcileAttachedVisibility([firstManaged.id: true])
        #expect(firstSurface.requestManagedFocus(true))

        #expect(firstDelivery.focusCalls == [.init(surfaceID: firstManaged.id, focused: true)])
        #expect(secondDelivery.focusCalls.isEmpty)
    }

    @Test("permanent release is exact and repeated release is a no-op")
    func permanentReleaseIsExactAndIdempotent() throws {
        let delivery = RecordingSurfaceRendererStateDelivery()
        let manager = makeManager(delivery: delivery)
        let managed = try acceptedSurface(makeBareSurface(), in: manager)

        let firstResult = manager.permanentlyRelease(managed.id, reason: .explicitTermination)
        let repeatedResult = manager.permanentlyRelease(managed.id, reason: .explicitTermination)

        #expect(firstResult == .released)
        #expect(repeatedResult == .notOwned)
        #expect(manager.managedSurface(for: managed.id) == nil)
        #expect(managed.surface.requestManagedFocus(true) == false)
    }

    private func makeManager(
        delivery: RecordingSurfaceRendererStateDelivery
    ) -> SurfaceManager {
        SurfaceManager(
            undoTTL: 300,
            maxCreationRetries: 0,
            healthCheckInterval: 3600,
            delayScheduler: AsyncDelay { _ in },
            now: { Date(timeIntervalSince1970: 1000) },
            rendererStateDelivery: delivery
        )
    }

    private func makeBareSurface() -> Ghostty.SurfaceView {
        Ghostty.SurfaceView(
            bareManagedSurfaceID: UUIDv7.generate(),
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
}

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
