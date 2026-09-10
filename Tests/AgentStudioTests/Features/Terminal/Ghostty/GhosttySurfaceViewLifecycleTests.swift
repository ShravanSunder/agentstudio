import AgentStudioCore
import AgentStudioInfrastructure
import AppKit
import Foundation
import Testing

@testable import AgentStudioTerminal

@MainActor
@Suite("GhosttySurfaceViewLifecycleTests", .serialized)
struct GhosttySurfaceViewLifecycleTests {
    @Test("bare surface has no native handle and deinitializes without a native free")
    func bareSurfaceDeinitializesWithoutNativeHandle() {
        // Arrange
        weak var weakSurface: Ghostty.SurfaceView?

        // Act
        autoreleasepool {
            var surface: Ghostty.SurfaceView? = Ghostty.SurfaceView(
                managedSurfaceID: UUIDv7.generate(),
                appCommandDispatcher: LifecycleNoOpAppCommandDispatcher()
            )
            weakSurface = surface
            #expect(surface?.surface == nil)
            surface = nil
        }

        // Assert
        #expect(weakSurface == nil)
    }

    @Test("retirement detaches a retained view and clears its host callbacks")
    func retirementDetachesRetainedView() {
        let parent = NSView()
        let surface = Ghostty.SurfaceView(
            managedSurfaceID: UUIDv7.generate(),
            appCommandDispatcher: LifecycleNoOpAppCommandDispatcher())
        surface.wantsLayer = true
        parent.addSubview(surface)
        surface.onCloseRequested = { _ in }

        surface.retireNativeSurface()
        surface.retireNativeSurface()

        #expect(surface.superview == nil)
        #expect(surface.layer == nil)
        #expect(surface.onCloseRequested == nil)
        #expect(surface.surface == nil)
        withExtendedLifetime(surface) {}
    }

    @Test("live delivery reports no side effect for a bare surface")
    func liveDeliveryReportsNoSideEffectForBareSurface() {
        // Arrange
        let surface = Ghostty.SurfaceView(
            managedSurfaceID: UUIDv7.generate(),
            appCommandDispatcher: LifecycleNoOpAppCommandDispatcher()
        )

        // Act
        let visibilityDelivered = LiveSurfaceRendererStateDelivery.shared.deliverVisibility(false, to: surface)
        let focusDelivered = LiveSurfaceRendererStateDelivery.shared.deliverFocus(false, to: surface)

        // Assert
        #expect(visibilityDelivered == false)
        #expect(focusDelivered == false)
    }
}

@MainActor
private final class LifecycleNoOpAppCommandDispatcher: AppCommandDispatching {
    func dispatch(_: AppCommand) {}
    func dispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) {}
    func canDispatch(_: AppCommand) -> Bool { false }
    func canDispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool { false }
    func bridgePaneCommandTarget(worktreeId _: UUID) -> BridgePaneCommandTarget? { nil }
    func dispatchMovePaneToTab(sourcePaneId _: UUID, sourceTabId _: UUID?, targetTabId _: UUID) {}
}
