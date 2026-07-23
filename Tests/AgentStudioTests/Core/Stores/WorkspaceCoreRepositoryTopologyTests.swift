import Foundation
import Testing

@testable import AgentStudio

@Suite("WorkspaceCoreRepositoryTopologyTests")
struct WorkspaceCoreRepositoryTopologyTests {
    @Test("repository topology round trips watched paths repos worktrees and unavailable repos")
    func repositoryTopologyRoundTripsWatchedPathsReposWorktreesAndUnavailableRepos() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Topology",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let repoId = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let mainWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let featureWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
        let topology = WorkspaceCoreRepository.RepositoryTopologyRecord(
            watchedPaths: [
                .init(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
                    path: URL(fileURLWithPath: "/tmp/agentstudio/watch-a"),
                    addedAt: Date(timeIntervalSince1970: 150)
                )
            ],
            repos: [
                .init(
                    id: repoId,
                    name: "repo-a",
                    repoPath: URL(fileURLWithPath: "/tmp/agentstudio/repo-a"),
                    createdAt: Date(timeIntervalSince1970: 200),
                    worktrees: [
                        .init(
                            id: mainWorktreeId,
                            repoId: repoId,
                            name: "repo-a",
                            path: URL(fileURLWithPath: "/tmp/agentstudio/repo-a"),
                            isMainWorktree: true,
                            note: "stable main"
                        ),
                        .init(
                            id: featureWorktreeId,
                            repoId: repoId,
                            name: "feature",
                            path: URL(fileURLWithPath: "/tmp/agentstudio/repo-a-feature"),
                            isMainWorktree: false,
                            note: "review work"
                        ),
                    ],
                    tags: ["client", "primary"]
                )
            ],
            unavailableRepoIds: [repoId]
        )

        try repository.replaceRepositoryTopology(topology)
        let restoredTopology = try repository.fetchRepositoryTopology()

        #expect(restoredTopology == topology)
    }

    @Test("repository topology replacement prunes removed repo tags")
    func repositoryTopologyReplacementPrunesRemovedRepoTags() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000128")!
        let repoId = UUID(uuidString: "00000000-0000-0000-0000-000000000235")!
        let worktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000329")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Tag Replacement",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try repository.replaceRepositoryTopology(
            .init(
                watchedPaths: [],
                repos: [
                    .init(
                        id: repoId,
                        name: "repo",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/tag-replacement-repo"),
                        createdAt: Date(timeIntervalSince1970: 200),
                        worktrees: [
                            .init(
                                id: worktreeId,
                                repoId: repoId,
                                name: "main",
                                path: URL(fileURLWithPath: "/tmp/agentstudio/tag-replacement-repo"),
                                isMainWorktree: true
                            )
                        ],
                        tags: ["old"]
                    )
                ],
                unavailableRepoIds: []
            )
        )

        try repository.replaceRepositoryTopology(
            .init(
                watchedPaths: [],
                repos: [
                    .init(
                        id: repoId,
                        name: "repo",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/tag-replacement-repo"),
                        createdAt: Date(timeIntervalSince1970: 200),
                        worktrees: [
                            .init(
                                id: worktreeId,
                                repoId: repoId,
                                name: "main",
                                path: URL(fileURLWithPath: "/tmp/agentstudio/tag-replacement-repo"),
                                isMainWorktree: true
                            )
                        ],
                        tags: ["new"]
                    )
                ],
                unavailableRepoIds: []
            )
        )
        let restoredTopology = try repository.fetchRepositoryTopology()

        #expect(restoredTopology.repos.single?.tags == ["new"])
    }

    @Test("repository sidebar metadata mutations target global topology")
    func repositorySidebarMetadataMutationsTargetGlobalTopology() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let repoId = UUID(uuidString: "00000000-0000-0000-0000-000000000238")!
        let worktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000330")!
        try repository.replaceRepositoryTopology(
            .init(
                watchedPaths: [],
                repos: [
                    .init(
                        id: repoId,
                        name: "metadata-repo",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/metadata-repo"),
                        createdAt: Date(timeIntervalSince1970: 200),
                        worktrees: [
                            .init(
                                id: worktreeId,
                                repoId: repoId,
                                name: "main",
                                path: URL(fileURLWithPath: "/tmp/agentstudio/metadata-repo"),
                                isMainWorktree: true
                            )
                        ]
                    )
                ],
                unavailableRepoIds: []
            )
        )

        try repository.updateRepoFavorite(repoId: repoId, isFavorite: true)
        try repository.updateRepoNote(repoId: repoId, note: "important")
        try repository.updateWorktreeNote(worktreeId: worktreeId, note: "review")
        try repository.replaceRepoTags(repoId: repoId, tags: ["client", "primary"])
        let restoredTopology = try repository.fetchRepositoryTopology()
        let restoredTags = try repository.fetchRepoTags(repoId: repoId)

        #expect(restoredTopology.repos.single?.isFavorite == true)
        #expect(restoredTopology.repos.single?.note == "important")
        #expect(restoredTopology.repos.single?.worktrees.single?.note == "review")
        #expect(restoredTags == ["client", "primary"])
    }

    @Test("repository topology is application global and survives workspace deletion")
    func repositoryTopologyIsApplicationGlobalAndSurvivesWorkspaceDeletion() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let firstWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let secondWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        try repository.upsertWorkspace(
            .init(
                id: firstWorkspaceId,
                name: "First",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try repository.upsertWorkspace(
            .init(
                id: secondWorkspaceId,
                name: "Second",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let repoId = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let topology = WorkspaceCoreRepository.RepositoryTopologyRecord(
            watchedPaths: [],
            repos: [
                .init(
                    id: repoId,
                    name: "global-repo",
                    repoPath: URL(fileURLWithPath: "/tmp/agentstudio/global-repo"),
                    createdAt: Date(timeIntervalSince1970: 200),
                    worktrees: [
                        .init(
                            id: UUID(uuidString: "00000000-0000-0000-0000-000000000303")!,
                            repoId: repoId,
                            name: "global-repo",
                            path: URL(fileURLWithPath: "/tmp/agentstudio/global-repo"),
                            isMainWorktree: true
                        )
                    ]
                )
            ],
            unavailableRepoIds: [repoId]
        )
        try repository.replaceRepositoryTopology(topology)

        _ = try repository.deleteWorkspace(firstWorkspaceId, updatedAt: Date(timeIntervalSince1970: 300))
        let restoredTopology = try repository.fetchRepositoryTopology()

        #expect(restoredTopology == topology)
        #expect(try repository.fetchWorkspace(id: secondWorkspaceId)?.id == secondWorkspaceId)
    }

    @Test("unavailable repo update rejects a missing global repository")
    func unavailableRepoUpdateRejectsMissingGlobalRepository() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let missingRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000204")!

        #expect(throws: WorkspaceCoreRepositoryError.repoNotFound(missingRepoId)) {
            try repository.setUnavailableRepoIds([missingRepoId])
        }
    }

    @Test("worktree reconciliation replaces rows without transient stable key conflicts")
    func worktreeReconciliationReplacesRowsWithoutTransientStableKeyConflicts() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000106")!
        let repoId = UUID(uuidString: "00000000-0000-0000-0000-000000000205")!
        let reusedWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000305")!
        let leavingWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000306")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Reconcile",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try repository.replaceRepositoryTopology(
            .init(
                watchedPaths: [],
                repos: [
                    .init(
                        id: repoId,
                        name: "repo",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/reconcile-repo"),
                        createdAt: Date(timeIntervalSince1970: 200),
                        worktrees: [
                            .init(
                                id: reusedWorktreeId,
                                repoId: repoId,
                                name: "old-a",
                                path: URL(fileURLWithPath: "/tmp/agentstudio/reconcile-old-a"),
                                isMainWorktree: true
                            ),
                            .init(
                                id: leavingWorktreeId,
                                repoId: repoId,
                                name: "old-b",
                                path: URL(fileURLWithPath: "/tmp/agentstudio/reconcile-reused-key"),
                                isMainWorktree: false
                            ),
                        ]
                    )
                ],
                unavailableRepoIds: []
            )
        )
        let reconciledWorktree = WorkspaceCoreRepository.WorktreeRecord(
            id: reusedWorktreeId,
            repoId: repoId,
            name: "reused-key",
            path: URL(fileURLWithPath: "/tmp/agentstudio/reconcile-reused-key"),
            isMainWorktree: true
        )

        try repository.reconcileRepoWorktrees(
            repoId: repoId,
            worktrees: [reconciledWorktree]
        )
        let restoredTopology = try repository.fetchRepositoryTopology()

        #expect(restoredTopology.repos.single?.worktrees == [reconciledWorktree])
    }

    @Test("worktree reconciliation swaps stable keys between retained worktrees")
    func worktreeReconciliationSwapsStableKeysBetweenRetainedWorktrees() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000122")!
        let repoId = UUID(uuidString: "00000000-0000-0000-0000-000000000228")!
        let firstWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000322")!
        let secondWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000323")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Worktree Stable Swap",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try repository.replaceRepositoryTopology(
            .init(
                watchedPaths: [],
                repos: [
                    .init(
                        id: repoId,
                        name: "repo",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/worktree-stable-swap-repo"),
                        createdAt: Date(timeIntervalSince1970: 200),
                        worktrees: [
                            .init(
                                id: firstWorktreeId,
                                repoId: repoId,
                                name: "first",
                                path: URL(fileURLWithPath: "/tmp/agentstudio/worktree-stable-swap-first"),
                                stableKey: "worktree-stable-key-a",
                                isMainWorktree: true
                            ),
                            .init(
                                id: secondWorktreeId,
                                repoId: repoId,
                                name: "second",
                                path: URL(fileURLWithPath: "/tmp/agentstudio/worktree-stable-swap-second"),
                                stableKey: "worktree-stable-key-b",
                                isMainWorktree: false
                            ),
                        ]
                    )
                ],
                unavailableRepoIds: []
            )
        )
        let swappedWorktrees = [
            WorkspaceCoreRepository.WorktreeRecord(
                id: firstWorktreeId,
                repoId: repoId,
                name: "first-swapped",
                path: URL(fileURLWithPath: "/tmp/agentstudio/worktree-stable-swap-first-renamed"),
                stableKey: "worktree-stable-key-b",
                isMainWorktree: true
            ),
            WorkspaceCoreRepository.WorktreeRecord(
                id: secondWorktreeId,
                repoId: repoId,
                name: "second-swapped",
                path: URL(fileURLWithPath: "/tmp/agentstudio/worktree-stable-swap-second-renamed"),
                stableKey: "worktree-stable-key-a",
                isMainWorktree: false
            ),
        ]

        try repository.reconcileRepoWorktrees(
            repoId: repoId,
            worktrees: swappedWorktrees
        )
        let restoredTopology = try repository.fetchRepositoryTopology()

        #expect(restoredTopology.repos.single?.worktrees == swappedWorktrees)
    }

}
