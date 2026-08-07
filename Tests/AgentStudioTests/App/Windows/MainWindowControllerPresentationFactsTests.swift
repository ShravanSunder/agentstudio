import AppKit
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInboxNotification
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct MainWindowControllerPresentationFactsTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("real window delegate ingress publishes presentation facts under the supplied UUID")
    func realWindowDelegateIngressPublishesPresentationFactsUnderSuppliedUUID() async throws {
        await withPresentationFactsWindowHarness { harness in
            // Arrange
            #expect(harness.windowLifecycleStore.registeredWindowIds.contains(harness.windowId))
            #expect(harness.windowLifecycleStore.presentationFacts(for: UUID()) == nil)

            // Act — publish the real NSWindow properties through a real delegate callback.
            harness.window.orderFront(nil)
            harness.controller.windowDidChangeOcclusionState(
                Notification(
                    name: NSWindow.didChangeOcclusionStateNotification,
                    object: harness.window
                )
            )

            // Assert
            #expect(
                harness.windowLifecycleStore.presentationFacts(for: harness.windowId)
                    == presentationFacts(of: harness.window)
            )

            // Act — transition the actual NSWindow to hidden and publish again.
            harness.window.orderOut(nil)
            harness.controller.windowDidChangeOcclusionState(
                Notification(
                    name: NSWindow.didChangeOcclusionStateNotification,
                    object: harness.window
                )
            )

            // Assert
            #expect(harness.window.isVisible == false)
            #expect(
                harness.windowLifecycleStore.presentationFacts(for: harness.windowId)
                    == presentationFacts(of: harness.window)
            )

            // Act — close ingress is terminal presentation, independent of physical WKWebView visibility.
            harness.controller.windowWillClose(
                Notification(name: NSWindow.willCloseNotification, object: harness.window)
            )

            // Assert
            #expect(
                harness.windowLifecycleStore.presentationFacts(for: harness.windowId)
                    == WindowPresentationFacts(
                        isVisible: false,
                        isMiniaturized: harness.window.isMiniaturized,
                        isOccluded: true
                    )
            )
        }
    }

    private func presentationFacts(of window: NSWindow) -> WindowPresentationFacts {
        WindowPresentationFacts(
            isVisible: window.isVisible,
            isMiniaturized: window.isMiniaturized,
            isOccluded: !window.occlusionState.contains(.visible)
        )
    }
}

@MainActor
private struct PresentationFactsWindowHarness {
    let windowId: UUID
    let windowLifecycleStore: WindowLifecycleAtom
    let controller: MainWindowController
    let window: NSWindow
}

@MainActor
private func withPresentationFactsWindowHarness<T>(
    body: @MainActor (PresentationFactsWindowHarness) async throws -> T
) async rethrows -> T {
    let atoms = makeTestAtomRegistry()
    let store = WorkspaceStore(
        identityAtom: atoms.core.workspaceIdentity,
        windowMemoryAtom: atoms.core.workspaceWindowMemory,
        repositoryTopologyAtom: atoms.core.workspaceRepositoryTopology,
        paneAtom: atoms.core.workspacePane,
        tabLayoutAtom: atoms.core.workspaceTabLayout,
        mutationCoordinator: atoms.core.workspaceMutationCoordinator
    )
    let viewRegistry = ViewRegistry()
    let appLifecycleStore = AppLifecycleAtom()
    let coordinator = WorkspaceSurfaceCoordinator(
        store: store,
        viewRegistry: viewRegistry,
        runtime: SessionRuntime(atom: atoms.core.sessionRuntime, store: store),
        surfaceManager: PresentationFactsWindowSurfaceManager(),
        runtimeRegistry: RuntimeRegistry(),
        windowLifecycleStore: atoms.core.windowLifecycle,
        appLifecycleStore: appLifecycleStore,
        bridgePaneAttendance: atoms.bridgePaneAttendance
    )
    let applicationLifecycleMonitor = ApplicationLifecycleMonitor(
        appLifecycleStore: appLifecycleStore,
        windowLifecycleStore: atoms.core.windowLifecycle
    )
    let windowId = UUID()
    var controller: MainWindowController?

    let result = try await withAsyncTestCoreAtoms(using: atoms.core) { _ in
        let windowController = MainWindowController(
            workspaceWindowId: windowId,
            store: store,
            octiconLoader: makeTestOcticonLoader(),
            workspaceActionExecutor: WorkspaceActionExecutor(
                coordinator: coordinator,
                store: store
            ),
            runtimeCommandDispatcher: coordinator,
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            tabBarAdapter: TabBarAdapter(
                store: store,
                repoCache: atoms.core.repoCache,
                inboxAtom: atoms.inboxNotification
            ),
            viewRegistry: viewRegistry,
            bridgePaneAttendance: atoms.bridgePaneAttendance,
            editorChooser: atoms.editorChooser,
            inboxAtom: atoms.inboxNotification,
            inboxPrefsAtom: InboxNotificationPrefsAtom(),
            inboxSidebarState: InboxSidebarState(),
            paneInboxPresentationState: atoms.paneInboxPresentationState,
            repoExplorerSidebarPrefs: atoms.repoExplorerSidebarPrefs,
            bridgeAttendanceSnapshot: {
                atoms.bridgePaneAttendance.ordinalSnapshot()
            },
            paneInboxPresenter: PaneInboxNotificationPresenter()
        )
        controller = windowController
        windowController.showWindow(nil)
        let window = try #require(windowController.window)
        return try await body(
            PresentationFactsWindowHarness(
                windowId: windowId,
                windowLifecycleStore: atoms.core.windowLifecycle,
                controller: windowController,
                window: window
            )
        )
    }

    (controller?.window?.contentViewController as? MainSplitViewController)?.shutdown()
    controller?.close()
    await coordinator.shutdown()
    return result
}

@MainActor
private final class PresentationFactsWindowSurfaceManager: WorkspaceSurfaceManaging {
    private let cwdChanges = AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { continuation in
        continuation.finish()
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> {
        cwdChanges
    }

    func syncFocus(activeSurfaceId: UUID?) {}

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        .failure(.ghosttyNotInitialized)
    }

    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? {
        nil
    }

    func requeueUndo(_ surfaceId: UUID) {}

    func destroy(_ surfaceId: UUID) {}
}
