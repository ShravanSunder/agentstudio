import Foundation
import Testing

@testable import AgentStudio

@Suite("WorkspaceCoreRepositoryTopologyReferenceTests")
struct WorkspaceCoreRepositoryTopologyReferenceTests {
    @Test("repository topology replace updates retained repo across stable key collision")
    func repositoryTopologyReplaceUpdatesRetainedRepoAcrossStableKeyCollision() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repository = fixture.repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000115")!
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000504")!
        let retainedRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000217")!
        let removedRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000218")!
        let retainedWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000314")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Repo Collision",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try repository.replaceRepositoryTopology(
            .init(
                watchedPaths: [],
                repos: [
                    .init(
                        id: retainedRepoId,
                        name: "old-a",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/repo-collision-old-a"),
                        createdAt: Date(timeIntervalSince1970: 200),
                        worktrees: [
                            .init(
                                id: retainedWorktreeId,
                                repoId: retainedRepoId,
                                name: "old-a",
                                path: URL(fileURLWithPath: "/tmp/agentstudio/repo-collision-old-a"),
                                isMainWorktree: true
                            )
                        ]
                    ),
                    .init(
                        id: removedRepoId,
                        name: "old-b",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/repo-collision-reused-key"),
                        createdAt: Date(timeIntervalSince1970: 250),
                        worktrees: []
                    ),
                ],
                unavailableRepoIds: []
            )
        )
        try fixture.insertPane(
            workspaceId: workspaceId,
            paneId: paneId,
            sourceRepoId: retainedRepoId,
            sourceWorktreeId: retainedWorktreeId
        )
        let reconciledRepo = WorkspaceCoreRepository.RepoRecord(
            id: retainedRepoId,
            name: "reused-key",
            repoPath: URL(fileURLWithPath: "/tmp/agentstudio/repo-collision-reused-key"),
            createdAt: Date(timeIntervalSince1970: 300),
            worktrees: [
                .init(
                    id: retainedWorktreeId,
                    repoId: retainedRepoId,
                    name: "reused-key",
                    path: URL(fileURLWithPath: "/tmp/agentstudio/repo-collision-reused-key"),
                    isMainWorktree: true
                )
            ]
        )

        try repository.replaceRepositoryTopology(
            .init(watchedPaths: [], repos: [reconciledRepo], unavailableRepoIds: [])
        )
        let restoredTopology = try repository.fetchRepositoryTopology()
        let paneSource = try fixture.fetchPaneSource(paneId: paneId)

        #expect(restoredTopology.repos == [reconciledRepo])
        #expect(paneSource?.repoId == retainedRepoId)
        #expect(paneSource?.worktreeId == retainedWorktreeId)
    }

    @Test("repository topology replace swaps stable keys between retained repos")
    func repositoryTopologyReplaceSwapsStableKeysBetweenRetainedRepos() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000121")!
        let firstRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000226")!
        let secondRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000227")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Repo Stable Swap",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try repository.replaceRepositoryTopology(
            .init(
                watchedPaths: [],
                repos: [
                    .init(
                        id: firstRepoId,
                        name: "first",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/stable-swap-first"),
                        stableKey: "repo-stable-key-a",
                        createdAt: Date(timeIntervalSince1970: 200),
                        worktrees: []
                    ),
                    .init(
                        id: secondRepoId,
                        name: "second",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/stable-swap-second"),
                        stableKey: "repo-stable-key-b",
                        createdAt: Date(timeIntervalSince1970: 250),
                        worktrees: []
                    ),
                ],
                unavailableRepoIds: []
            )
        )
        let swappedTopology = WorkspaceCoreRepository.RepositoryTopologyRecord(
            watchedPaths: [],
            repos: [
                .init(
                    id: firstRepoId,
                    name: "first-swapped",
                    repoPath: URL(fileURLWithPath: "/tmp/agentstudio/stable-swap-first-renamed"),
                    stableKey: "repo-stable-key-b",
                    createdAt: Date(timeIntervalSince1970: 200),
                    worktrees: []
                ),
                .init(
                    id: secondRepoId,
                    name: "second-swapped",
                    repoPath: URL(fileURLWithPath: "/tmp/agentstudio/stable-swap-second-renamed"),
                    stableKey: "repo-stable-key-a",
                    createdAt: Date(timeIntervalSince1970: 250),
                    worktrees: []
                ),
            ],
            unavailableRepoIds: []
        )

        try repository.replaceRepositoryTopology(swappedTopology)
        let restoredTopology = try repository.fetchRepositoryTopology()

        #expect(restoredTopology == swappedTopology)
    }

    @Test("two workspace compositions may reference the same global repo and worktree")
    func twoWorkspaceCompositionsMayReferenceSameGlobalRepoAndWorktree() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repository = fixture.repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000107")!
        let secondWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000108")!
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
        let secondPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000000509")!
        let repoId = UUID(uuidString: "00000000-0000-0000-0000-000000000206")!
        let worktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000307")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Source References",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try repository.upsertWorkspace(
            .init(
                id: secondWorkspaceId,
                name: "Second Source References",
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
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/source-repo"),
                        createdAt: Date(timeIntervalSince1970: 200),
                        worktrees: [
                            .init(
                                id: worktreeId,
                                repoId: repoId,
                                name: "repo",
                                path: URL(fileURLWithPath: "/tmp/agentstudio/source-repo"),
                                isMainWorktree: true
                            )
                        ]
                    )
                ],
                unavailableRepoIds: []
            )
        )
        try fixture.insertPane(
            workspaceId: workspaceId,
            paneId: paneId,
            sourceRepoId: repoId,
            sourceWorktreeId: worktreeId
        )
        try fixture.insertPane(
            workspaceId: secondWorkspaceId,
            paneId: secondPaneId,
            sourceRepoId: repoId,
            sourceWorktreeId: worktreeId
        )

        try repository.replaceRepositoryTopology(
            .init(
                watchedPaths: [],
                repos: [
                    .init(
                        id: repoId,
                        name: "repo-renamed",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/source-repo-renamed"),
                        createdAt: Date(timeIntervalSince1970: 250),
                        worktrees: [
                            .init(
                                id: worktreeId,
                                repoId: repoId,
                                name: "renamed",
                                path: URL(fileURLWithPath: "/tmp/agentstudio/source-repo-renamed"),
                                isMainWorktree: true
                            )
                        ]
                    )
                ],
                unavailableRepoIds: []
            )
        )
        let firstPaneSource = try fixture.fetchPaneSource(paneId: paneId)
        let secondPaneSource = try fixture.fetchPaneSource(paneId: secondPaneId)

        #expect(firstPaneSource?.repoId == repoId)
        #expect(firstPaneSource?.worktreeId == worktreeId)
        #expect(secondPaneSource?.repoId == repoId)
        #expect(secondPaneSource?.worktreeId == worktreeId)
    }

    @Test("worktree reconciliation preserves pane source worktree for retained worktree")
    func worktreeReconciliationPreservesPaneSourceWorktreeForRetainedWorktree() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repository = fixture.repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000108")!
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000502")!
        let repoId = UUID(uuidString: "00000000-0000-0000-0000-000000000207")!
        let retainedWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000308")!
        let removedWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000309")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Retained Worktree",
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
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/retained-worktree-repo"),
                        createdAt: Date(timeIntervalSince1970: 200),
                        worktrees: [
                            .init(
                                id: retainedWorktreeId,
                                repoId: repoId,
                                name: "old-a",
                                path: URL(fileURLWithPath: "/tmp/agentstudio/retained-worktree-old-a"),
                                isMainWorktree: true
                            ),
                            .init(
                                id: removedWorktreeId,
                                repoId: repoId,
                                name: "old-b",
                                path: URL(fileURLWithPath: "/tmp/agentstudio/retained-worktree-reused-key"),
                                isMainWorktree: false
                            ),
                        ]
                    )
                ],
                unavailableRepoIds: []
            )
        )
        try fixture.insertPane(
            workspaceId: workspaceId,
            paneId: paneId,
            sourceRepoId: repoId,
            sourceWorktreeId: retainedWorktreeId
        )

        try repository.reconcileRepoWorktrees(
            repoId: repoId,
            worktrees: [
                .init(
                    id: retainedWorktreeId,
                    repoId: repoId,
                    name: "reused-key",
                    path: URL(fileURLWithPath: "/tmp/agentstudio/retained-worktree-reused-key"),
                    isMainWorktree: true
                )
            ]
        )
        let paneSource = try fixture.fetchPaneSource(paneId: paneId)

        #expect(paneSource?.repoId == repoId)
        #expect(paneSource?.worktreeId == retainedWorktreeId)
    }

    @Test("worktree reconciliation nulls only source worktree when referenced worktree is removed")
    func worktreeReconciliationNullsOnlySourceWorktreeWhenReferencedWorktreeIsRemoved() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repository = fixture.repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000116")!
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000505")!
        let repoId = UUID(uuidString: "00000000-0000-0000-0000-000000000219")!
        let removedWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000315")!
        let retainedWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000316")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Remove Worktree",
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
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/remove-worktree-repo"),
                        createdAt: Date(timeIntervalSince1970: 200),
                        worktrees: [
                            .init(
                                id: removedWorktreeId,
                                repoId: repoId,
                                name: "removed",
                                path: URL(fileURLWithPath: "/tmp/agentstudio/remove-worktree-removed"),
                                isMainWorktree: true
                            ),
                            .init(
                                id: retainedWorktreeId,
                                repoId: repoId,
                                name: "retained",
                                path: URL(fileURLWithPath: "/tmp/agentstudio/remove-worktree-retained"),
                                isMainWorktree: false
                            ),
                        ]
                    )
                ],
                unavailableRepoIds: []
            )
        )
        try fixture.insertPane(
            workspaceId: workspaceId,
            paneId: paneId,
            sourceRepoId: repoId,
            sourceWorktreeId: removedWorktreeId
        )

        try repository.reconcileRepoWorktrees(
            repoId: repoId,
            worktrees: [
                .init(
                    id: retainedWorktreeId,
                    repoId: repoId,
                    name: "retained",
                    path: URL(fileURLWithPath: "/tmp/agentstudio/remove-worktree-retained"),
                    isMainWorktree: true
                )
            ]
        )
        let paneSource = try fixture.fetchPaneSource(paneId: paneId)

        #expect(paneSource?.repoId == repoId)
        #expect(paneSource?.worktreeId == nil)
    }

    @Test("repository topology replace nulls repo and worktree source when referenced repo is removed")
    func repositoryTopologyReplaceNullsRepoAndWorktreeSourceWhenReferencedRepoIsRemoved() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repository = fixture.repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000117")!
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000506")!
        let removedRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000220")!
        let retainedRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000221")!
        let removedWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000317")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Remove Repo",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try repository.replaceRepositoryTopology(
            .init(
                watchedPaths: [],
                repos: [
                    .init(
                        id: removedRepoId,
                        name: "removed",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/remove-repo-removed"),
                        createdAt: Date(timeIntervalSince1970: 200),
                        worktrees: [
                            .init(
                                id: removedWorktreeId,
                                repoId: removedRepoId,
                                name: "removed",
                                path: URL(fileURLWithPath: "/tmp/agentstudio/remove-repo-removed"),
                                isMainWorktree: true
                            )
                        ]
                    ),
                    .init(
                        id: retainedRepoId,
                        name: "retained",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/remove-repo-retained"),
                        createdAt: Date(timeIntervalSince1970: 250),
                        worktrees: []
                    ),
                ],
                unavailableRepoIds: []
            )
        )
        try fixture.insertPane(
            workspaceId: workspaceId,
            paneId: paneId,
            sourceRepoId: removedRepoId,
            sourceWorktreeId: removedWorktreeId
        )

        try repository.replaceRepositoryTopology(
            .init(
                watchedPaths: [],
                repos: [
                    .init(
                        id: retainedRepoId,
                        name: "retained",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/remove-repo-retained"),
                        createdAt: Date(timeIntervalSince1970: 250),
                        worktrees: []
                    )
                ],
                unavailableRepoIds: []
            )
        )
        let paneSource = try fixture.fetchPaneSource(paneId: paneId)

        #expect(paneSource?.repoId == nil)
        #expect(paneSource?.worktreeId == nil)
    }

}
