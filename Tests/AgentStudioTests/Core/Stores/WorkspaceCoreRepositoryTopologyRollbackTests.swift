import Foundation
import Testing

@testable import AgentStudio

@Suite("WorkspaceCoreRepositoryTopologyRollbackTests")
struct WorkspaceCoreRepositoryTopologyRollbackTests {
    @Test("unavailable repository replacement rolls back after a missing global repo")
    func unavailableRepositoryReplacementRollsBackAfterMissingGlobalRepo() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repository = fixture.repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000118")!
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000507")!
        let watchedPathId = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!
        let originalRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000222")!
        let missingRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000223")!
        let originalWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000318")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Rollback Source",
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
        try repository.replaceRepositoryTopology(originalTopology)
        try fixture.insertPane(
            workspaceId: workspaceId,
            paneId: paneId,
            sourceRepoId: originalRepoId,
            sourceWorktreeId: originalWorktreeId
        )

        #expect(throws: WorkspaceCoreRepositoryError.repoNotFound(missingRepoId)) {
            try repository.setUnavailableRepoIds([originalRepoId, missingRepoId])
        }
        let restoredTopology = try repository.fetchRepositoryTopology()
        let paneSource = try fixture.fetchPaneSource(paneId: paneId)

        #expect(restoredTopology == originalTopology)
        #expect(paneSource?.repoId == originalRepoId)
        #expect(paneSource?.worktreeId == originalWorktreeId)
    }

    @Test("worktree reconciliation rolls back after existing worktree reparenting")
    func worktreeReconciliationRollsBackAfterExistingWorktreeReparenting() throws {
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
        try repository.replaceRepositoryTopology(originalTopology)
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
        let restoredTopology = try repository.fetchRepositoryTopology()
        let paneSource = try fixture.fetchPaneSource(paneId: paneId)

        #expect(restoredTopology == originalTopology)
        #expect(paneSource?.repoId == targetRepoId)
        #expect(paneSource?.worktreeId == removedWorktreeId)
    }
}
