import AppKit
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSurfaceCoordinator cross-tab move view transitions")
struct WorkspaceCrossTabMoveTransitionTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("cross-tab move detaches moved and source-left panes but reattaches only destination visibility transitions")
    func crossTabMoveTransitionsExcludeDestinationPanesThatWereAlreadyVisible() {
        let movedPane = UUID()
        let sourceLeftPane = UUID()
        let existingDestinationPane = UUID()
        let otherExistingDestinationPane = UUID()

        let transitions = WorkspaceSurfaceCoordinator.computeCrossTabMoveViewTransitions(
            sourceVisibleBefore: [movedPane, sourceLeftPane],
            destinationVisibleBefore: [existingDestinationPane, otherExistingDestinationPane],
            destinationVisibleAfter: [
                movedPane,
                existingDestinationPane,
                otherExistingDestinationPane,
            ],
            movedPaneIds: [movedPane]
        )

        #expect(transitions.paneIdsToDetach == [movedPane, sourceLeftPane])
        #expect(transitions.paneIdsToReattach == [movedPane])
    }

    @Test("cross-tab move reattaches moved drawer children visible in the destination active view")
    func crossTabMoveTransitionsReattachVisibleMovedDrawerChildren() {
        let movedParentPane = UUID()
        let visibleMovedDrawerChildPane = UUID()
        let existingDestinationPane = UUID()

        let transitions = WorkspaceSurfaceCoordinator.computeCrossTabMoveViewTransitions(
            sourceVisibleBefore: [movedParentPane],
            destinationVisibleBefore: [existingDestinationPane],
            destinationVisibleAfter: [movedParentPane, existingDestinationPane, visibleMovedDrawerChildPane],
            movedPaneIds: [movedParentPane, visibleMovedDrawerChildPane]
        )

        #expect(transitions.paneIdsToDetach == [movedParentPane, visibleMovedDrawerChildPane])
        #expect(transitions.paneIdsToReattach == [movedParentPane, visibleMovedDrawerChildPane])
    }

    @Test("cross-tab move detaches destination panes that transition from visible to hidden")
    func crossTabMoveTransitionsDetachDestinationPanesThatBecomeHidden() {
        let movedPane = UUID()
        let sourceLeftPane = UUID()
        let remainingDestinationPane = UUID()
        let hiddenDestinationPane = UUID()

        let transitions = WorkspaceSurfaceCoordinator.computeCrossTabMoveViewTransitions(
            sourceVisibleBefore: [movedPane, sourceLeftPane],
            destinationVisibleBefore: [remainingDestinationPane, hiddenDestinationPane],
            destinationVisibleAfter: [movedPane, remainingDestinationPane],
            movedPaneIds: [movedPane]
        )

        #expect(transitions.paneIdsToDetach == [movedPane, sourceLeftPane, hiddenDestinationPane])
        #expect(transitions.paneIdsToReattach == [movedPane])
    }

    @Test("executeMovePaneAcrossTabs reattaches only moved pane, not already-visible destination panes")
    func executeMovePaneAcrossTabsReattachesOnlyMovedDestinationDelta() {
        withTestAtomRegistry { atoms in
            atoms.managementLayer.deactivate()

            let tempDir = FileManager.default.temporaryDirectory
                .appending(path: "agentstudio-cross-tab-move-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let store = WorkspaceStore(
                workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner())
            let viewRegistry = ViewRegistry()
            let surfaceManager = CrossTabMoveSurfaceManager()
            let coordinator = WorkspaceSurfaceCoordinator(
                store: store,
                viewRegistry: viewRegistry,
                runtime: SessionRuntime(store: store),
                surfaceManager: surfaceManager,
                runtimeRegistry: RuntimeRegistry(),
                windowLifecycleStore: WindowLifecycleAtom()
            )

            let movedPane = store.createPane(title: "A")
            let sourceLeftPane = store.createPane(title: "B")
            let existingDestinationPane = store.createPane(title: "C")
            let otherExistingDestinationPane = store.createPane(title: "D")

            let sourceTab = Tab(paneId: movedPane.id)
            let destinationTab = Tab(paneId: existingDestinationPane.id)
            store.appendTab(sourceTab)
            store.appendTab(destinationTab)
            #expect(
                store.insertPane(
                    sourceLeftPane.id,
                    inTab: sourceTab.id,
                    at: movedPane.id,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )
            )
            #expect(
                store.insertPane(
                    otherExistingDestinationPane.id,
                    inTab: destinationTab.id,
                    at: existingDestinationPane.id,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )
            )

            let surfaceIdsByPaneId = [
                movedPane.id: UUID(),
                sourceLeftPane.id: UUID(),
                existingDestinationPane.id: UUID(),
                otherExistingDestinationPane.id: UUID(),
            ]
            surfaceManager.paneIdsBySurfaceId = Dictionary(
                uniqueKeysWithValues: surfaceIdsByPaneId.map { paneId, surfaceId in
                    (surfaceId, paneId)
                }
            )
            for (paneId, surfaceId) in surfaceIdsByPaneId {
                registerTerminalHost(
                    viewRegistry: viewRegistry,
                    paneId: paneId,
                    surfaceId: surfaceId
                )
            }

            coordinator.executeMovePaneAcrossTabs(
                CrossTabPaneMoveRequest(
                    paneId: movedPane.id,
                    sourceTabId: sourceTab.id,
                    destTabId: destinationTab.id,
                    targetPaneId: existingDestinationPane.id,
                    direction: .horizontal,
                    position: .after
                )
            )

            #expect(surfaceManager.attachedPaneIds == [movedPane.id])
            #expect(Set(surfaceManager.detachedPaneIds) == [movedPane.id, sourceLeftPane.id])
            #expect(!surfaceManager.attachedPaneIds.contains(existingDestinationPane.id))
            #expect(!surfaceManager.attachedPaneIds.contains(otherExistingDestinationPane.id))
        }
    }

    @Test("executeMovePaneAcrossTabs reattaches moved drawer children visible in destination")
    func executeMovePaneAcrossTabsReattachesVisibleMovedDrawerChildren() throws {
        try withTestAtomRegistry { atoms in
            atoms.managementLayer.deactivate()

            let tempDir = FileManager.default.temporaryDirectory
                .appending(path: "agentstudio-cross-tab-drawer-move-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let store = WorkspaceStore(
                workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner())
            let viewRegistry = ViewRegistry()
            let surfaceManager = CrossTabMoveSurfaceManager()
            let coordinator = WorkspaceSurfaceCoordinator(
                store: store,
                viewRegistry: viewRegistry,
                runtime: SessionRuntime(store: store),
                surfaceManager: surfaceManager,
                runtimeRegistry: RuntimeRegistry(),
                windowLifecycleStore: WindowLifecycleAtom()
            )

            let movedPane = store.createPane(title: "A")
            let sourceLeftPane = store.createPane(title: "B")
            let existingDestinationPane = store.createPane(title: "C")

            let sourceTab = Tab(paneId: movedPane.id)
            let destinationTab = Tab(paneId: existingDestinationPane.id)
            store.appendTab(sourceTab)
            store.appendTab(destinationTab)
            store.setActiveTab(destinationTab.id)
            #expect(
                store.insertPane(
                    sourceLeftPane.id,
                    inTab: sourceTab.id,
                    at: movedPane.id,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )
            )
            let drawerPane = try #require(store.addDrawerPane(to: movedPane.id))

            let surfaceIdsByPaneId = [
                movedPane.id: UUID(),
                sourceLeftPane.id: UUID(),
                existingDestinationPane.id: UUID(),
                drawerPane.id: UUID(),
            ]
            surfaceManager.paneIdsBySurfaceId = Dictionary(
                uniqueKeysWithValues: surfaceIdsByPaneId.map { paneId, surfaceId in
                    (surfaceId, paneId)
                }
            )
            for (paneId, surfaceId) in surfaceIdsByPaneId {
                registerTerminalHost(
                    viewRegistry: viewRegistry,
                    paneId: paneId,
                    surfaceId: surfaceId
                )
            }

            coordinator.executeMovePaneAcrossTabs(
                CrossTabPaneMoveRequest(
                    paneId: movedPane.id,
                    sourceTabId: sourceTab.id,
                    destTabId: destinationTab.id,
                    targetPaneId: existingDestinationPane.id,
                    direction: .horizontal,
                    position: .after
                )
            )

            #expect(Set(surfaceManager.attachedPaneIds) == [movedPane.id, drawerPane.id])
            #expect(Set(surfaceManager.detachedPaneIds) == [movedPane.id, sourceLeftPane.id, drawerPane.id])
            #expect(!surfaceManager.attachedPaneIds.contains(existingDestinationPane.id))
        }
    }

    private func registerTerminalHost(
        viewRegistry: ViewRegistry,
        paneId: UUID,
        surfaceId: UUID
    ) {
        let host = PaneHostView(paneId: paneId)
        let terminalView = TerminalPaneMountView(restoredSurfaceId: surfaceId, paneId: paneId)
        host.mountContentView(terminalView)
        viewRegistry.register(host, for: paneId)
    }
}

@MainActor
private final class CrossTabMoveSurfaceManager: WorkspaceSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>

    var paneIdsBySurfaceId: [UUID: UUID] = [:]
    private(set) var attachedPaneIds: [UUID] = []
    private(set) var detachedPaneIds: [UUID] = []

    init() {
        self.cwdStream = AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { continuation in
            continuation.finish()
        }
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { cwdStream }

    func syncFocus(activeSurfaceId: UUID?) {}

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        .failure(.ghosttyNotInitialized)
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        attachedPaneIds.append(paneId)
        return nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {
        guard let paneId = paneIdsBySurfaceId[surfaceId] else { return }
        detachedPaneIds.append(paneId)
    }

    func undoClose() -> ManagedSurface? { nil }

    func requeueUndo(_ surfaceId: UUID) {}

    func destroy(_ surfaceId: UUID) {}
}
