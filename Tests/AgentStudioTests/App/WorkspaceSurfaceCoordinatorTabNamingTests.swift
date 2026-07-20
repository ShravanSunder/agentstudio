import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceSurfaceCoordinatorTabNamingTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test
    func test_tabNameForPane_distinctBranch_usesFolderAndBranch() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir.appending(path: "repo-distinct"))
        let worktree = Worktree(repoId: repo.id, name: "feature", path: repo.repoPath.appending(path: "feature"))
        harness.store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        let storedWorktree = try #require(harness.store.repos.first?.worktrees.first, "Expected stored worktree")
        atom(\.repoCache).setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: storedWorktree.id, repoId: repo.id, branch: "feature/login")
        )

        let pane = harness.store.createPane(
            launchDirectory: storedWorktree.path,
            title: "Ignored",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: storedWorktree.id, cwd: storedWorktree.path),
        )

        #expect(harness.coordinator.tabNameForPane(pane) == "feature · feature/login")
    }

    @Test
    func test_tabNameForPane_detachedHead_usesFolderNameOnly() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir.appending(path: "repo-detached"))
        let worktree = Worktree(repoId: repo.id, name: "feature", path: repo.repoPath.appending(path: "feature"))
        harness.store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        let storedWorktree = try #require(harness.store.repos.first?.worktrees.first, "Expected stored worktree")
        atom(\.repoCache).setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: storedWorktree.id, repoId: repo.id, branch: "detached HEAD")
        )

        let pane = harness.store.createPane(
            launchDirectory: storedWorktree.path,
            title: "Ignored",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: storedWorktree.id, cwd: storedWorktree.path),
        )

        #expect(harness.coordinator.tabNameForPane(pane) == "feature")
    }

    @Test
    func test_tabNameForPane_emptyBranch_usesFolderNameOnly() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir.appending(path: "repo-empty"))
        let worktree = Worktree(repoId: repo.id, name: "feature", path: repo.repoPath.appending(path: "feature"))
        harness.store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        let storedWorktree = try #require(harness.store.repos.first?.worktrees.first, "Expected stored worktree")
        atom(\.repoCache).setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: storedWorktree.id, repoId: repo.id, branch: "")
        )

        let pane = harness.store.createPane(
            launchDirectory: storedWorktree.path,
            title: "Ignored",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: storedWorktree.id, cwd: storedWorktree.path),
        )

        #expect(harness.coordinator.tabNameForPane(pane) == "feature")
    }

    @Test
    func test_tabNameForPane_branchMatchingFolder_usesSingleName() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir.appending(path: "repo-match"))
        let worktree = Worktree(repoId: repo.id, name: "feature", path: repo.repoPath.appending(path: "feature"))
        harness.store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        let storedWorktree = try #require(harness.store.repos.first?.worktrees.first, "Expected stored worktree")
        atom(\.repoCache).setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: storedWorktree.id, repoId: repo.id, branch: "feature")
        )

        let pane = harness.store.createPane(
            launchDirectory: storedWorktree.path,
            title: "Ignored",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: storedWorktree.id, cwd: storedWorktree.path),
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
