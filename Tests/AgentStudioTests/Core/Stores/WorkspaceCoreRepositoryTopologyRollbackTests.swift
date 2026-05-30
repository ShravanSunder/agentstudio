import Foundation
import Testing

@testable import AgentStudio

@Suite("WorkspaceCoreRepositoryTopologyRollbackTests")
struct WorkspaceCoreRepositoryTopologyRollbackTests {
    @Test("repository topology replace rolls back after foreign repo conflict")
    func repositoryTopologyReplaceRollsBackAfterForeignRepoConflict() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repository = fixture.repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000118")!
        let otherWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000119")!
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000507")!
        let watchedPathId = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!
        let originalRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000222")!
        let foreignRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000223")!
        let originalWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000318")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Rollback Source",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try repository.upsertWorkspace(
            .init(
                id: otherWorkspaceId,
                name: "Rollback Other",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let originalTopology = WorkspaceCoreRepository.RepositoryTopologyRecord(
            watchedPaths: [
                .init(
                    id: watchedPathId,
                    path: URL(fileURLWithPath: "/tmp/agentstudio/rollback-watch"),
                    addedAt: Date(timeIntervalSince1970: 150)
                )
            ],
            repos: [
                .init(
                    id: originalRepoId,
                    name: "original",
                    repoPath: URL(fileURLWithPath: "/tmp/agentstudio/rollback-original"),
                    createdAt: Date(timeIntervalSince1970: 200),
                    worktrees: [
                        .init(
                            id: originalWorktreeId,
                            repoId: originalRepoId,
                            name: "original",
                            path: URL(fileURLWithPath: "/tmp/agentstudio/rollback-original"),
                            isMainWorktree: true
                        )
                    ]
                )
            ],
            unavailableRepoIds: [originalRepoId]
        )
        try repository.replaceRepositoryTopology(workspaceId: workspaceId, topology: originalTopology)
        try repository.replaceRepositoryTopology(
            workspaceId: otherWorkspaceId,
            topology: .init(
                watchedPaths: [],
                repos: [
                    .init(
                        id: foreignRepoId,
                        name: "foreign",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/rollback-foreign"),
                        createdAt: Date(timeIntervalSince1970: 250),
                        worktrees: []
                    )
                ],
                unavailableRepoIds: []
            )
        )
        try fixture.insertPane(
            workspaceId: workspaceId,
            paneId: paneId,
            sourceRepoId: originalRepoId,
            sourceWorktreeId: originalWorktreeId
        )

        #expect(throws: WorkspaceCoreRepositoryError.repoNotFoundInWorkspace(foreignRepoId, workspaceId)) {
            try repository.replaceRepositoryTopology(
                workspaceId: workspaceId,
                topology: .init(
                    watchedPaths: [],
                    repos: [
                        .init(
                            id: foreignRepoId,
                            name: "foreign",
                            repoPath: URL(fileURLWithPath: "/tmp/agentstudio/rollback-foreign"),
                            createdAt: Date(timeIntervalSince1970: 250),
                            worktrees: []
                        )
                    ],
                    unavailableRepoIds: []
                )
            )
        }
        let restoredTopology = try repository.fetchRepositoryTopology(workspaceId: workspaceId)
        let paneSource = try fixture.fetchPaneSource(paneId: paneId)

        #expect(restoredTopology == originalTopology)
        #expect(paneSource?.repoId == originalRepoId)
        #expect(paneSource?.worktreeId == originalWorktreeId)
    }

    @Test("worktree reconciliation rolls back after foreign worktree conflict")
    func worktreeReconciliationRollsBackAfterForeignWorktreeConflict() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repository = fixture.repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000120")!
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000508")!
        let targetRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000224")!
        let otherRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000225")!
        let retainedWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000319")!
        let removedWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000320")!
        let foreignWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000321")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Worktree Rollback",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let originalTopology = WorkspaceCoreRepository.RepositoryTopologyRecord(
            watchedPaths: [],
            repos: [
                .init(
                    id: targetRepoId,
                    name: "target",
                    repoPath: URL(fileURLWithPath: "/tmp/agentstudio/worktree-rollback-target"),
                    createdAt: Date(timeIntervalSince1970: 200),
                    worktrees: [
                        .init(
                            id: retainedWorktreeId,
                            repoId: targetRepoId,
                            name: "retained",
                            path: URL(fileURLWithPath: "/tmp/agentstudio/worktree-rollback-retained"),
                            isMainWorktree: true
                        ),
                        .init(
                            id: removedWorktreeId,
                            repoId: targetRepoId,
                            name: "removed",
                            path: URL(fileURLWithPath: "/tmp/agentstudio/worktree-rollback-removed"),
                            isMainWorktree: false
                        ),
                    ]
                ),
                .init(
                    id: otherRepoId,
                    name: "other",
                    repoPath: URL(fileURLWithPath: "/tmp/agentstudio/worktree-rollback-other"),
                    createdAt: Date(timeIntervalSince1970: 250),
                    worktrees: [
                        .init(
                            id: foreignWorktreeId,
                            repoId: otherRepoId,
                            name: "foreign",
                            path: URL(fileURLWithPath: "/tmp/agentstudio/worktree-rollback-foreign"),
                            isMainWorktree: true
                        )
                    ]
                ),
            ],
            unavailableRepoIds: []
        )
        try repository.replaceRepositoryTopology(workspaceId: workspaceId, topology: originalTopology)
        try fixture.insertPane(
            workspaceId: workspaceId,
            paneId: paneId,
            sourceRepoId: targetRepoId,
            sourceWorktreeId: removedWorktreeId
        )

        #expect(
            throws: WorkspaceCoreRepositoryError.worktreeRepoMismatch(
                worktreeId: foreignWorktreeId,
                expectedRepoId: targetRepoId,
                actualRepoId: otherRepoId
            )
        ) {
            try repository.reconcileRepoWorktrees(
                workspaceId: workspaceId,
                repoId: targetRepoId,
                worktrees: [
                    .init(
                        id: retainedWorktreeId,
                        repoId: targetRepoId,
                        name: "retained-updated",
                        path: URL(fileURLWithPath: "/tmp/agentstudio/worktree-rollback-retained-updated"),
                        isMainWorktree: true
                    ),
                    .init(
                        id: foreignWorktreeId,
                        repoId: targetRepoId,
                        name: "foreign-reparented",
                        path: URL(fileURLWithPath: "/tmp/agentstudio/worktree-rollback-foreign-reparented"),
                        isMainWorktree: false
                    ),
                ]
            )
        }
        let restoredTopology = try repository.fetchRepositoryTopology(workspaceId: workspaceId)
        let paneSource = try fixture.fetchPaneSource(paneId: paneId)

        #expect(restoredTopology == originalTopology)
        #expect(paneSource?.repoId == targetRepoId)
        #expect(paneSource?.worktreeId == removedWorktreeId)
    }
}
