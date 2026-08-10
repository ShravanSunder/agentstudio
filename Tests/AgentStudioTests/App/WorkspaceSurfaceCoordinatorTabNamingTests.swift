import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct WorkspaceSurfaceCoordinatorTabNamingTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test
    func test_tabNameForPane_distinctBranch_usesFolderAndBranch() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let topology = try addRepositoryWithFeatureWorktree(
            at: harness.tempDir.appending(path: "repo-distinct"),
            to: harness.store
        )
        atom(\.repoCache).setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: topology.worktree.id,
                repoId: topology.repository.id,
                branch: "feature/login"
            )
        )

        let pane = harness.store.createPane(
            launchDirectory: topology.worktree.path,
            title: "Ignored",
            facets: PaneContextFacets(
                repoId: topology.repository.id,
                worktreeId: topology.worktree.id,
                cwd: topology.worktree.path
            ),
        )

        #expect(harness.coordinator.tabNameForPane(pane) == "feature · feature/login")
    }

    @Test
    func test_tabNameForPane_detachedHead_usesFolderNameOnly() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let topology = try addRepositoryWithFeatureWorktree(
            at: harness.tempDir.appending(path: "repo-detached"),
            to: harness.store
        )
        atom(\.repoCache).setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: topology.worktree.id,
                repoId: topology.repository.id,
                branch: "detached HEAD"
            )
        )

        let pane = harness.store.createPane(
            launchDirectory: topology.worktree.path,
            title: "Ignored",
            facets: PaneContextFacets(
                repoId: topology.repository.id,
                worktreeId: topology.worktree.id,
                cwd: topology.worktree.path
            ),
        )

        #expect(harness.coordinator.tabNameForPane(pane) == "feature")
    }

    @Test
    func test_tabNameForPane_emptyBranch_usesFolderNameOnly() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let topology = try addRepositoryWithFeatureWorktree(
            at: harness.tempDir.appending(path: "repo-empty"),
            to: harness.store
        )
        atom(\.repoCache).setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: topology.worktree.id, repoId: topology.repository.id, branch: "")
        )

        let pane = harness.store.createPane(
            launchDirectory: topology.worktree.path,
            title: "Ignored",
            facets: PaneContextFacets(
                repoId: topology.repository.id,
                worktreeId: topology.worktree.id,
                cwd: topology.worktree.path
            ),
        )

        #expect(harness.coordinator.tabNameForPane(pane) == "feature")
    }

    @Test
    func test_tabNameForPane_branchMatchingFolder_usesSingleName() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let topology = try addRepositoryWithFeatureWorktree(
            at: harness.tempDir.appending(path: "repo-match"),
            to: harness.store
        )
        atom(\.repoCache).setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: topology.worktree.id,
                repoId: topology.repository.id,
                branch: "feature"
            )
        )

        let pane = harness.store.createPane(
            launchDirectory: topology.worktree.path,
            title: "Ignored",
            facets: PaneContextFacets(
                repoId: topology.repository.id,
                worktreeId: topology.worktree.id,
                cwd: topology.worktree.path
            ),
        )

        #expect(harness.coordinator.tabNameForPane(pane) == "feature")
    }

    @Test
    func test_tabNameForPane_emptyFloatingTitle_fallsBackToTerminal() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(
            title: "   "
        )

        #expect(harness.coordinator.tabNameForPane(pane) == "Terminal")
    }

    private func addRepositoryWithFeatureWorktree(
        at repositoryPath: URL,
        to store: WorkspaceStore
    ) throws -> (repository: Repo, worktree: Worktree) {
        let repository = store.addRepo(at: repositoryPath)
        let existingMainWorktree = repository.worktrees.first(where: \.isMainWorktree)
        let mainWorktree = try #require(existingMainWorktree, "Expected repository main worktree")
        let linkedWorktree = Worktree(
            repoId: repository.id,
            name: "feature",
            path: repository.repoPath.appending(path: "feature")
        )
        store.reconcileDiscoveredWorktrees(
            repository.id,
            worktrees: [mainWorktree, linkedWorktree]
        )
        let storedLinkedWorktree = try #require(
            store.worktree(linkedWorktree.id),
            "Expected stored linked worktree"
        )
        return (repository, storedLinkedWorktree)
    }

    private func makeHarness() -> (store: WorkspaceStore, coordinator: WorkspaceSurfaceCoordinator, tempDir: URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "pane-coordinator-naming-\(UUID().uuidString)")
        let store = WorkspaceStore()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: TabNamingSurfaceManager(),
            runtimeRegistry: RuntimeRegistry()
        )
        return (store, coordinator, tempDir)
    }
}

private final class TabNamingSurfaceManager: WorkspaceSurfaceManaging {
    private let cwdStream = AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { continuation in
        continuation.onTermination = { _ in }
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { cwdStream }

    func syncFocus(activeSurfaceId _: UUID?) {}

    func createSurface(
        config _: Ghostty.SurfaceConfiguration,
        metadata _: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        .failure(.operationFailed("mock"))
    }

    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        _ = surfaceId
        _ = paneId
        return nil
    }

    func detach(_ surfaceId: UUID, reason _: SurfaceDetachReason) {
        _ = surfaceId
    }

    func undoClose() -> ManagedSurface? { nil }

    func requeueUndo(_ surfaceId: UUID) {
        _ = surfaceId
    }

    func destroy(_ surfaceId: UUID) {
        _ = surfaceId
    }
}
