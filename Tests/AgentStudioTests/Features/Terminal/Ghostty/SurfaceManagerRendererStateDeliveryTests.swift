import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudioTerminal

@MainActor
@Suite("SurfaceManagerRendererStateDeliveryTests", .serialized)
struct SurfaceManagerRendererStateDeliveryTests {

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

    @Test("accepting a created surface delivers hidden visibility")
    func acceptingCreatedSurfaceDeliversHidden() throws {
        // Arrange
        let delivery = RecordingSurfaceRendererStateDelivery()
        let manager = makeManager(delivery: delivery)
        let surface = makeBareSurface()

        // Act
        let managed = try acceptedSurface(surface, in: manager)

        // Assert
        #expect(
            delivery.visibilityCalls == [
                .init(surfaceID: managed.id, visible: false)
            ]
        )
        #expect(managed.lastDeliveredVisibility == false)
        #expect(manager.hiddenSurfaceCount == 1)
    }

    @Test("detach delivers hidden while the surface is still attached")
    func detachDeliversHiddenWhileSurfaceIsStillAttached() throws {
        // Arrange
        let delivery = RecordingSurfaceRendererStateDelivery()
        let manager = makeManager(delivery: delivery)
        let surface = makeBareSurface()
        let managed = try acceptedSurface(surface, in: manager)
        let paneID = UUIDv7.generate()
        manager.attach(managed.id, to: paneID)
        delivery.reset()

        var wasAttached = false
        delivery.onVisibilityDelivery = { _, visible in
            if !visible {
                wasAttached = manager.activeSurfaceIds.contains(managed.id)
            }
        }

        // Act
        manager.detach(managed.id, reason: .hide)

        // Assert
        #expect(wasAttached == true)
        #expect(delivery.visibilityCalls == [.init(surfaceID: managed.id, visible: false)])
        #expect(delivery.focusCalls == [.init(surfaceID: managed.id, focused: false)])
        #expect(manager.activeSurfaceCount == 0)
        #expect(manager.hiddenSurfaceCount == 1)
    }

    @Test("attach delivers visible and an equal reconciliation delivers nothing")
    func attachDeliversVisibleAndEqualReconciliationDeliversNothing() throws {
        // Arrange
        let delivery = RecordingSurfaceRendererStateDelivery()
        let manager = makeManager(delivery: delivery)
        let surface = makeBareSurface()
        let managed = try acceptedSurface(surface, in: manager)
        let paneID = UUIDv7.generate()
        delivery.reset()

        // Act
        manager.attach(managed.id, to: paneID)

        // Assert
        #expect(delivery.visibilityCalls == [.init(surfaceID: managed.id, visible: true)])

        // Act
        let result = manager.reconcileAttachedVisibility { _ in true }

        // Assert
        #expect(result == .init(applied: 0, equal: 1, missing: 0))
        #expect(delivery.visibilityCalls == [.init(surfaceID: managed.id, visible: true)])
        #expect(delivery.focusCalls.isEmpty)
    }

    @Test("reconciliation delivers only changed surfaces")
    func reconciliationDeliversOnlyChangedSurfaces() throws {
        // Arrange
        let delivery = RecordingSurfaceRendererStateDelivery()
        let manager = makeManager(delivery: delivery)
        let surfaceA = makeBareSurface()
        let surfaceB = makeBareSurface()
        let managedA = try acceptedSurface(surfaceA, in: manager)
        let managedB = try acceptedSurface(surfaceB, in: manager)
        let paneA = UUIDv7.generate()
        let paneB = UUIDv7.generate()
        manager.attach(managedA.id, to: paneA)
        manager.attach(managedB.id, to: paneB)
        delivery.reset()

        // Act
        let firstResult = manager.reconcileAttachedVisibility { paneID in paneID != paneA }

        // Assert
        #expect(firstResult == .init(applied: 1, equal: 1, missing: 0))
        #expect(delivery.visibilityCalls == [.init(surfaceID: managedA.id, visible: false)])
        #expect(delivery.focusCalls == [.init(surfaceID: managedA.id, focused: false)])

        // Act
        let secondResult = manager.reconcileAttachedVisibility { paneID in paneID != paneA }

        // Assert
        #expect(secondResult == .init(applied: 0, equal: 2, missing: 0))
        #expect(delivery.visibilityCalls == [.init(surfaceID: managedA.id, visible: false)])
        #expect(delivery.focusCalls == [.init(surfaceID: managedA.id, focused: false)])
    }

    @Test("pane visibility closure receives only attached pane bindings")
    func paneVisibilityClosureReceivesOnlyAttachedPaneBindings() throws {
        // Arrange
        let delivery = RecordingSurfaceRendererStateDelivery()
        let manager = makeManager(delivery: delivery)
        let attachedSurface = makeBareSurface()
        let hiddenSurface = makeBareSurface()
        let managedAttached = try acceptedSurface(attachedSurface, in: manager)
        _ = try acceptedSurface(hiddenSurface, in: manager)
        let attachedPaneID = UUIDv7.generate()
        manager.attach(managedAttached.id, to: attachedPaneID)

        var seenPaneIDs: [UUID] = []

        // Act
        _ = manager.reconcileAttachedVisibility { paneID in
            seenPaneIDs.append(paneID)
            return true
        }

        // Assert
        #expect(seenPaneIDs == [attachedPaneID])
    }

    @Test("attached bindings handler fires on membership changes")
    func attachedBindingsHandlerFiresOnMembershipChanges() throws {
        // Arrange
        let delivery = RecordingSurfaceRendererStateDelivery()
        let manager = makeManager(delivery: delivery)
        let surface = makeBareSurface()
        let managed = try acceptedSurface(surface, in: manager)
        let paneID = UUIDv7.generate()
        let otherPaneID = UUIDv7.generate()
        var callCount = 0
        manager.setAttachedBindingsChangeHandler { callCount += 1 }

        // Act & Assert
        manager.attach(managed.id, to: paneID)
        #expect(callCount == 1)

        manager.move(managed.id, to: otherPaneID)
        #expect(callCount == 2)

        manager.detach(managed.id, reason: .hide)
        #expect(callCount == 3)

        manager.attach(managed.id, to: paneID)
        #expect(callCount == 4)

        manager.setAttachedBindingsChangeHandler(nil)
        manager.attach(managed.id, to: otherPaneID)
        #expect(callCount == 4)
    }

    @Test("closing a hidden surface enters undo")
    func closingHiddenSurfaceEntersUndo() throws {
        // Arrange
        let delivery = RecordingSurfaceRendererStateDelivery()
        let manager = makeManager(delivery: delivery)
        let surface = makeBareSurface()
        let managed = try acceptedSurface(surface, in: manager)
        let paneID = UUIDv7.generate()
        manager.attach(managed.id, to: paneID)
        manager.detach(managed.id, reason: .hide)
        delivery.reset()

        // Act
        manager.detach(managed.id, reason: .close)

        // Assert
        #expect(manager.hiddenSurfaceCount == 0)
        #expect(manager.canUndo == true)
        #expect(delivery.visibilityCalls.isEmpty)
        #expect(manager.activeSurfaceCount == 0)
    }

    @Test("requeueing for undo delivers hidden while the surface is still attached")
    func requeueUndoDeliversHiddenWhileAttached() throws {
        // Arrange
        let delivery = RecordingSurfaceRendererStateDelivery()
        let manager = makeManager(delivery: delivery)
        let surface = makeBareSurface()
        let managed = try acceptedSurface(surface, in: manager)
        let paneID = UUIDv7.generate()
        manager.attach(managed.id, to: paneID)
        delivery.reset()

        var wasAttached = false
        delivery.onVisibilityDelivery = { _, visible in
            if !visible {
                wasAttached = manager.activeSurfaceIds.contains(managed.id)
            }
        }

        // Act
        manager.requeueUndo(managed.id)

        // Assert
        #expect(wasAttached == true)
        #expect(delivery.visibilityCalls == [.init(surfaceID: managed.id, visible: false)])
        #expect(manager.canUndo == true)
    }

    @Test("focus-on is refused while delivered visibility is false")
    func focusOnIsRefusedWhileDeliveredVisibilityIsFalse() throws {
        // Arrange
        let delivery = RecordingSurfaceRendererStateDelivery()
        let manager = makeManager(delivery: delivery)
        let surface = makeBareSurface()
        let managed = try acceptedSurface(surface, in: manager)
        let paneID = UUIDv7.generate()
        manager.attach(managed.id, to: paneID)
        _ = manager.reconcileAttachedVisibility { _ in false }
        delivery.reset()

        // Act
        manager.setFocus(managed.id, focused: true)

        // Assert
        #expect(delivery.focusCalls.isEmpty)

        // Act
        manager.setFocus(managed.id, focused: false)

        // Assert
        #expect(delivery.focusCalls == [.init(surfaceID: managed.id, focused: false)])
    }

    @Test("syncFocus delivers focus-on only to the visible target")
    func syncFocusDeliversFocusOnOnlyToVisibleTarget() throws {
        // Arrange
        let delivery = RecordingSurfaceRendererStateDelivery()
        let manager = makeManager(delivery: delivery)
        let surfaceA = makeBareSurface()
        let surfaceB = makeBareSurface()
        let managedA = try acceptedSurface(surfaceA, in: manager)
        let managedB = try acceptedSurface(surfaceB, in: manager)
        let paneA = UUIDv7.generate()
        let paneB = UUIDv7.generate()
        manager.attach(managedA.id, to: paneA)
        manager.attach(managedB.id, to: paneB)
        _ = manager.reconcileAttachedVisibility { paneID in paneID != paneB }
        delivery.reset()

        // Act
        manager.syncFocus(activeSurfaceId: managedA.id)

        // Assert
        #expect(delivery.focusCalls.count == 2)
        #expect(delivery.focusCalls.contains(.init(surfaceID: managedA.id, focused: true)))
        #expect(delivery.focusCalls.contains(.init(surfaceID: managedB.id, focused: false)))

        // Act
        manager.syncFocus(activeSurfaceId: managedB.id)

        // Assert
        #expect(delivery.focusCalls.contains(.init(surfaceID: managedA.id, focused: false)))
        #expect(delivery.focusCalls.contains(.init(surfaceID: managedB.id, focused: false)))
        #expect(!delivery.focusCalls.contains(.init(surfaceID: managedB.id, focused: true)))
    }

    @Test("turning on does not deliver focus when the surface is not first responder")
    func turningOnDoesNotDeliverFocusWhenSurfaceIsNotFirstResponder() throws {
        // Arrange
        let delivery = RecordingSurfaceRendererStateDelivery()
        let manager = makeManager(delivery: delivery)
        let surface = makeBareSurface()
        let managed = try acceptedSurface(surface, in: manager)
        let paneID = UUIDv7.generate()
        manager.attach(managed.id, to: paneID)
        _ = manager.reconcileAttachedVisibility { _ in false }
        delivery.reset()

        // Act
        let result = manager.reconcileAttachedVisibility { _ in true }

        // Assert
        #expect(result == .init(applied: 1, equal: 0, missing: 0))
        #expect(delivery.visibilityCalls == [.init(surfaceID: managed.id, visible: true)])
        #expect(delivery.focusCalls.isEmpty)
    }
}

// MARK: - Test Doubles

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
