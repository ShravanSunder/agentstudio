import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("RepositoryTopologyStoreTests", .serialized)
struct RepositoryTopologyStoreTests {
    @Test("restore hydrates topology from resolved datastore context")
    func restoreHydratesTopologyFromResolvedDatastoreContext() async throws {
        let workspaceId = UUID()
        let repoId = UUID()
        let worktreeId = UUID()
        let watchedPathId = UUID()
        let context = try await makeResolvedRestoreContext(
            workspaceId: workspaceId,
            repoId: repoId,
            worktreeId: worktreeId,
            watchedPathId: watchedPathId
        )
        let store = RepositoryTopologyStore()

        store.startObserving()
        store.restoreTopology(from: context)

        #expect(store.repositoryTopologyAtom.repos.map(\.id) == [repoId])
        #expect(store.repositoryTopologyAtom.repos.single?.worktrees.map(\.id) == [worktreeId])
        #expect(store.repositoryTopologyAtom.watchedPaths.map(\.id) == [watchedPathId])
        #expect(store.repositoryTopologyAtom.unavailableRepoIds == [repoId])
        #expect(!store.isDirty)
    }

    @Test("observed topology mutation marks only repository topology store dirty")
    func observedTopologyMutationMarksOnlyRepositoryTopologyStoreDirty() async {
        let store = RepositoryTopologyStore()

        store.startObserving()
        _ = store.repositoryTopologyAtom.addRepo(at: URL(fileURLWithPath: "/tmp/repository-topology-dirty"))
        for _ in 0..<10 where !store.isDirty {
            await Task.yield()
        }

        #expect(store.isDirty)
    }

    private func makeResolvedRestoreContext(
        workspaceId: UUID,
        repoId: UUID,
        worktreeId: UUID,
        watchedPathId: UUID
    ) async throws -> WorkspaceSQLiteDatastore.ResolvedWorkspaceRestoreContext {
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.repository-topology-store.core"
        )
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.repository-topology-store.local"
        )
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: localQueue) }
        )
        let snapshot = WorkspaceSQLiteSnapshot(
            id: workspaceId,
            name: "Repository Topology Store",
            repos: [
                CanonicalRepo(
                    id: repoId,
                    name: "repository-topology-store",
                    repoPath: URL(fileURLWithPath: "/tmp/repository-topology-store")
                )
            ],
            worktrees: [
                CanonicalWorktree(
                    id: worktreeId,
                    repoId: repoId,
                    name: "main",
                    path: URL(fileURLWithPath: "/tmp/repository-topology-store/main"),
                    isMainWorktree: true
                )
            ],
            unavailableRepoIds: [repoId],
            watchedPaths: [
                WatchedPath(
                    id: watchedPathId,
                    path: URL(fileURLWithPath: "/tmp/repository-topology-watch"),
                    addedAt: Date(timeIntervalSince1970: 8)
                )
            ],
            updatedAt: Date(timeIntervalSince1970: 9)
        )
        try await datastore.saveWorkspaceSnapshot(snapshot)
        let result = await datastore.resolveWorkspaceRestoreContext(preferredWorkspaceId: workspaceId)
        guard case .resolved(let context) = result else {
            throw RepositoryTopologyStoreTestError.contextUnavailable
        }
        return context
    }
}

private enum RepositoryTopologyStoreTestError: Error {
    case contextUnavailable
}
