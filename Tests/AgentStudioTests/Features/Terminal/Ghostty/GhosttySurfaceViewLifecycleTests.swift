import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioTerminal

@MainActor
@Suite("GhosttySurfaceViewLifecycleTests", .serialized)
struct GhosttySurfaceViewLifecycleTests {
    @Test("bare surface keeps its focus requester weak")
    func bareSurfaceKeepsFocusRequesterWeak() {
        let surface = makeBareSurface()
        var requester: FocusRequesterProbe? = FocusRequesterProbe()
        let weakRequester = WeakFocusRequesterBox(requester)
        surface.focusRequester = requester

        requester = nil

        #expect(weakRequester.value == nil)
        #expect(surface.requestManagedFocus(true) == false)
    }

    @Test("bare surface deinitializes without attempting native free")
    func bareSurfaceDeinitializesWithoutNativeHandle() {
        weak var weakSurface: Ghostty.SurfaceView?

        autoreleasepool {
            var surface: Ghostty.SurfaceView? = makeBareSurface()
            weakSurface = surface
            #expect(surface?.surface == nil)
            surface = nil
        }

        #expect(weakSurface == nil)
    }

    @Test("final bare surface reference can be released off-main through isolated deinit")
    func finalBareSurfaceReferenceCanBeReleasedOffMain() async {
        var surface: Ghostty.SurfaceView? = makeBareSurface()
        let weakSurface = WeakSurfaceReference(surface)
        let releaseBox = OffMainSurfaceReleaseBox(surface)
        surface = nil

        // This test must drop the final reference off MainActor.
        // swiftlint:disable:next no_task_detached
        await Task.detached {
            await releaseBox.releaseThenDrainMainActor()
        }.value

        #expect(weakSurface.value == nil)
    }

    private func makeBareSurface() -> Ghostty.SurfaceView {
        Ghostty.SurfaceView(
            bareManagedSurfaceID: UUIDv7.generate(),
            appCommandDispatcher: LifecycleNoOpAppCommandDispatcher()
        )
    }
}

private final class OffMainSurfaceReleaseBox: @unchecked Sendable {
    private var surface: Ghostty.SurfaceView?

    init(_ surface: Ghostty.SurfaceView?) {
        self.surface = surface
    }

    func releaseThenDrainMainActor() async {
        surface = nil
        await MainActor.run {}
    }
}

@MainActor
private final class WeakSurfaceReference {
    weak var value: Ghostty.SurfaceView?

    init(_ value: Ghostty.SurfaceView?) {
        self.value = value
    }
}

@MainActor
private final class WeakFocusRequesterBox {
    weak var value: FocusRequesterProbe?

    init(_ value: FocusRequesterProbe?) {
        self.value = value
    }
}

@MainActor
private final class FocusRequesterProbe: SurfaceFocusRequesting {
    func requestFocus(
        surfaceID _: UUID,
        viewIdentity _: ObjectIdentifier,
        focused _: Bool
    ) -> Bool {
        true
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
