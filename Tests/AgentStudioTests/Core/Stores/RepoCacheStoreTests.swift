import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct RepoCacheStoreTests {
    private let tempDir: URL
    private let persistor: WorkspacePersistor

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "repo-cache-store-tests-\(UUID().uuidString)")
        persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
    }

    @Test
    func flushAndRestore_roundTripsPersistedCacheState() throws {
        let workspaceId = UUID()
        let atom = RepoCacheAtom()
        let repo = CanonicalRepo(
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio")
        )
        let worktree = CanonicalWorktree(
            repoId: repo.id,
            name: "main",
            path: URL(fileURLWithPath: "/tmp/agent-studio/main"),
            isMainWorktree: true
        )
        let repoStore = RepoCacheStore(atom: atom, persistor: persistor)

        atom.setRepoEnrichment(.awaitingOrigin(repoId: repo.id))
        atom.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktree.id, repoId: repo.id, branch: "main")
        )
        atom.setPullRequestCount(3, for: worktree.id)
        atom.setNotificationCount(2, for: worktree.id)
        atom.recordRecentTarget(
            .forCwd(
                URL(fileURLWithPath: "/tmp/agent-studio/main"),
                title: "agent-studio",
                subtitle: "main",
                lastOpenedAt: Date(timeIntervalSince1970: 456)
            )
        )
        atom.markRebuilt(sourceRevision: 42, at: Date(timeIntervalSince1970: 123))

        try repoStore.flush(for: workspaceId)

        let restoredAtom = RepoCacheAtom()
        let restoredStore = RepoCacheStore(atom: restoredAtom, persistor: persistor)
        restoredStore.restore(for: workspaceId)

        #expect(restoredAtom.repoEnrichmentByRepoId[repo.id] == .awaitingOrigin(repoId: repo.id))
        #expect(restoredAtom.worktreeEnrichmentByWorktreeId[worktree.id]?.branch == "main")
        #expect(restoredAtom.pullRequestCountByWorktreeId[worktree.id] == 3)
        #expect(restoredAtom.notificationCountByWorktreeId[worktree.id] == 2)
        #expect(restoredAtom.recentTargets.map(\.id) == ["cwd:/tmp/agent-studio/main"])
        #expect(restoredAtom.sourceRevision == 42)
        #expect(restoredAtom.lastRebuiltAt == Date(timeIntervalSince1970: 123))
    }
}
