import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
final class WorkspaceCacheCoordinatorTests {

    private func makeWorkspaceStore() -> WorkspaceStore {
        let tempDir = FileManager.default.temporaryDirectory.appending(
            path: "workspace-cache-coordinator-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        return WorkspaceStore(persistor: persistor)
    }

    @Test
    func topology_repoDiscovered_addsRepoToWorkspaceStore() {
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            cacheStore: cacheStore
        )

        let repoPath = URL(fileURLWithPath: "/tmp/luna-repo")
        let envelope = SystemEnvelope.test(
            event: .topology(.repoDiscovered(repoPath: repoPath, parentPath: repoPath.deletingLastPathComponent()))
        )

        coordinator.handleTopology(envelope)

        #expect(workspaceStore.repos.contains(where: { $0.repoPath == repoPath }))
    }

    @Test
    func enrichment_snapshotChanged_updatesWorktreeCache() {
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            cacheStore: cacheStore
        )

        let repoId = UUID()
        let worktreeId = UUID()
        let snapshot = GitWorkingTreeSnapshot(
            worktreeId: worktreeId,
            repoId: repoId,
            rootPath: URL(fileURLWithPath: "/tmp/repo"),
            summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
            branch: "main"
        )

        let envelope = WorktreeEnvelope.test(
            event: .gitWorkingDirectory(.snapshotChanged(snapshot: snapshot)),
            repoId: repoId,
            worktreeId: worktreeId,
            source: .system(.builtin(.gitWorkingDirectoryProjector))
        )

        coordinator.handleEnrichment(envelope)

        #expect(cacheStore.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "main")
        #expect(cacheStore.worktreeEnrichmentByWorktreeId[worktreeId]?.repoId == repoId)
    }

    @Test
    func enrichment_pullRequestCountsChanged_mapsByBranch() {
        let workspaceStore = makeWorkspaceStore()
        let cacheStore = WorkspaceCacheStore()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            cacheStore: cacheStore
        )

        let repoId = UUID()
        let worktreeId = UUID()
        cacheStore.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: worktreeId,
                repoId: repoId,
                branch: "feature/runtime"
            )
        )

        let envelope = WorktreeEnvelope.test(
            event: .forge(.pullRequestCountsChanged(repoId: repoId, countsByBranch: ["feature/runtime": 3])),
            repoId: repoId,
            worktreeId: nil,
            source: .system(.service(.gitForge(provider: "github")))
        )

        coordinator.handleEnrichment(envelope)

        #expect(cacheStore.pullRequestCountByWorktreeId[worktreeId] == 3)
    }
}
