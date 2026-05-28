import AppKit
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneCoordinatorArrangementSwitchHostTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private let trustedBounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    @Test("switchArrangement restores a newly visible terminal pane when its host is missing")
    func switchArrangement_restoresMissingNewlyVisibleTerminalView() {
        withTestAtomRegistry { atoms in
            atoms.managementLayer.deactivate()

            let harness = makeHarness()
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }

            let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
            let visiblePane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Visible")
            let hiddenPane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Hidden")
            let tab = Tab(paneId: visiblePane.id)
            harness.store.appendTab(tab)
            harness.store.insertPane(
                hiddenPane.id,
                inTab: tab.id,
                at: visiblePane.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
            let allPanesArrangementId = harness.store.createArrangement(name: "All panes", inTab: tab.id)!
            #expect(harness.store.minimizePane(hiddenPane.id, inTab: tab.id))
            harness.store.tabLayoutAtom.setShowsMinimizedPanes(false, inTab: tab.id)
            harness.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
            harness.windowLifecycleStore.recordLaunchLayoutSettled()

            #expect(harness.coordinator.arrangementView.activeVisiblePaneIds(forTab: tab.id) == [visiblePane.id])
            #expect(harness.viewRegistry.view(for: hiddenPane.id) == nil)

            harness.coordinator.execute(.switchArrangement(tabId: tab.id, arrangementId: allPanesArrangementId))

            #expect(harness.coordinator.arrangementView.activeVisiblePaneIds(forTab: tab.id).contains(hiddenPane.id))
            #expect(harness.viewRegistry.view(for: hiddenPane.id) != nil)
        }
    }

    private struct Harness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let coordinator: PaneCoordinator
        let windowLifecycleStore: WindowLifecycleAtom
        let tempDir: URL
    }

    private func makeHarness() -> Harness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-arrangement-switch-host-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let windowLifecycleStore = WindowLifecycleAtom()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: SessionRuntime(store: store),
            surfaceManager: ArrangementSwitchSurfaceManager(),
            runtimeRegistry: RuntimeRegistry(),
            windowLifecycleStore: windowLifecycleStore
        )
        return Harness(
            store: store,
            viewRegistry: viewRegistry,
            coordinator: coordinator,
            windowLifecycleStore: windowLifecycleStore,
            tempDir: tempDir
        )
    }

    private func makeRepoAndWorktree(_ store: WorkspaceStore, root: URL) -> (Repo, Worktree) {
        let repoPath = root.appending(path: "repo-\(UUID().uuidString)")
        let worktreePath = repoPath.appending(path: "wt-main")
        try? FileManager.default.createDirectory(at: worktreePath, withIntermediateDirectories: true)

        let repo = store.addRepo(at: repoPath)
        let worktree = Worktree(repoId: repo.id, name: "wt-main", path: worktreePath)
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        return (repo, worktree)
    }

    private func makeWorktreePane(
        _ store: WorkspaceStore,
        repo: Repo,
        worktree: Worktree,
        title: String
    ) -> Pane {
        store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: title,
            provider: .zmx
        )
    }
}

@MainActor
private final class ArrangementSwitchSurfaceManager: PaneCoordinatorSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>

    init() {
        cwdStream = AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { continuation in
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
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? { nil }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? { nil }

    func requeueUndo(_ surfaceId: UUID) {}

    func destroy(_ surfaceId: UUID) {}
}
