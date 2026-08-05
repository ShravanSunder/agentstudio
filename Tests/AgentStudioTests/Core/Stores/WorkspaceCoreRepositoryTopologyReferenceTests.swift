import Foundation
import Testing

@testable import AgentStudioCore

@Suite("WorkspaceCoreRepositoryTopologyReferenceTests")
struct WorkspaceCoreRepositoryTopologyReferenceTests {
    @Test("repository topology replace updates retained repo across stable key collision")
    func repositoryTopologyReplaceUpdatesRetainedRepoAcrossStableKeyCollision() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000115")!
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

        #expect(restoredTopology.repos == [reconciledRepo])
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

    @Test("two workspace pane CWDs remain independent of shared global topology")
    func twoWorkspacePaneCWDsRemainIndependentOfSharedGlobalTopology() throws {
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
            cwd: URL(fileURLWithPath: "/tmp/agentstudio/source-repo/Sources")
        )
        try fixture.insertPane(
            workspaceId: secondWorkspaceId,
            paneId: secondPaneId,
            cwd: URL(fileURLWithPath: "/tmp/agentstudio/source-repo/Sources")
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
        let firstPane = try repository.fetchPaneGraph(workspaceId: workspaceId).panes.single
        let secondPane = try repository.fetchPaneGraph(workspaceId: secondWorkspaceId).panes.single

        #expect(firstPane?.metadata.durableFacets.cwd?.path == "/tmp/agentstudio/source-repo/Sources")
        #expect(secondPane?.metadata.durableFacets.cwd?.path == "/tmp/agentstudio/source-repo/Sources")
    }

    @Test("worktree reconciliation preserves pane CWD for retained worktree")
    func worktreeReconciliationPreservesPaneCWDForRetainedWorktree() throws {
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
            cwd: URL(fileURLWithPath: "/tmp/agentstudio/retained-worktree-old-a/Sources")
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
        let pane = try repository.fetchPaneGraph(workspaceId: workspaceId).panes.single

        #expect(pane?.metadata.durableFacets.cwd?.path == "/tmp/agentstudio/retained-worktree-old-a/Sources")
    }

    @Test("worktree reconciliation preserves pane CWD when containing worktree is removed")
    func worktreeReconciliationPreservesPaneCWDWhenContainingWorktreeIsRemoved() throws {
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
            cwd: URL(fileURLWithPath: "/tmp/agentstudio/remove-worktree-removed/Sources")
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
        let pane = try repository.fetchPaneGraph(workspaceId: workspaceId).panes.single

        #expect(pane?.metadata.durableFacets.cwd?.path == "/tmp/agentstudio/remove-worktree-removed/Sources")
    }

    @Test("repository topology replacement preserves pane CWD when containing repo is removed")
    func repositoryTopologyReplacementPreservesPaneCWDWhenContainingRepoIsRemoved() throws {
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
            cwd: URL(fileURLWithPath: "/tmp/agentstudio/remove-repo-removed/Sources")
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
        let pane = try repository.fetchPaneGraph(workspaceId: workspaceId).panes.single

        #expect(pane?.metadata.durableFacets.cwd?.path == "/tmp/agentstudio/remove-repo-removed/Sources")
    }

}
