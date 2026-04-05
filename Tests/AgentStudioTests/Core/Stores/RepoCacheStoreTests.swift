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

    @Test
    func flush_operatesOnTheProvidedLiveAtomScope() throws {
        let workspaceId = UUID()
        let atom = RepoCacheAtom()
        let store = RepoCacheStore(atom: atom, persistor: persistor)
        let repo = CanonicalRepo(
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio")
        )

        atom.setRepoEnrichment(.awaitingOrigin(repoId: repo.id))

        try store.flush(for: workspaceId)

        let restoredAtom = RepoCacheAtom()
        RepoCacheStore(atom: restoredAtom, persistor: persistor).restore(for: workspaceId)

        #expect(restoredAtom.repoEnrichmentByRepoId[repo.id] == .awaitingOrigin(repoId: repo.id))
    }

    @Test
    func restore_corruptCacheFile_fallsBackToDefaults() throws {
        let workspaceId = UUID()
        let corruptURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.cache.json")
        try "not json".write(to: corruptURL, atomically: true, encoding: .utf8)

        let atom = RepoCacheAtom()
        let repoStore = RepoCacheStore(atom: atom, persistor: persistor)

        repoStore.restore(for: workspaceId)

        #expect(atom.repoEnrichmentByRepoId.isEmpty)
        #expect(atom.worktreeEnrichmentByWorktreeId.isEmpty)
        #expect(atom.pullRequestCountByWorktreeId.isEmpty)
        #expect(atom.notificationCountByWorktreeId.isEmpty)
        #expect(atom.recentTargets.isEmpty)
    }
}
