import Foundation
import Testing

@testable import AgentStudio

@Suite("WorkspaceCoreRepositoryTopologyValidationTests")
struct WorkspaceCoreRepositoryTopologyValidationTests {
    @Test("repository topology replace rejects unavailable repo outside topology")
    func repositoryTopologyReplaceRejectsUnavailableRepoOutsideTopology() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000109")!
        let missingRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000208")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Unavailable Validation",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )

        #expect(throws: WorkspaceCoreRepositoryError.unavailableRepoNotInTopology(missingRepoId)) {
            try repository.replaceRepositoryTopology(
                workspaceId: workspaceId,
                topology: .init(watchedPaths: [], repos: [], unavailableRepoIds: [missingRepoId])
            )
        }
    }

    @Test("repository topology replace rejects worktree assigned to different repo")
    func repositoryTopologyReplaceRejectsWorktreeAssignedToDifferentRepo() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000110")!
        let repoId = UUID(uuidString: "00000000-0000-0000-0000-000000000209")!
        let otherRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000210")!
        let worktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000310")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Worktree Validation",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )

        #expect(
            throws: WorkspaceCoreRepositoryError.worktreeRepoMismatch(
                worktreeId: worktreeId,
                expectedRepoId: repoId,
                actualRepoId: otherRepoId
            )
        ) {
            try repository.replaceRepositoryTopology(
                workspaceId: workspaceId,
                topology: .init(
                    watchedPaths: [],
                    repos: [
                        .init(
                            id: repoId,
                            name: "repo",
                            repoPath: URL(fileURLWithPath: "/tmp/agentstudio/worktree-validation"),
                            createdAt: Date(timeIntervalSince1970: 200),
                            worktrees: [
                                .init(
                                    id: worktreeId,
                                    repoId: otherRepoId,
                                    name: "other",
                                    path: URL(fileURLWithPath: "/tmp/agentstudio/worktree-validation"),
                                    isMainWorktree: true
                                )
                            ]
                        )
                    ],
                    unavailableRepoIds: []
                )
            )
        }
    }

    @Test("repository topology replace rejects reparenting an existing worktree id to a different repo")
    func repositoryTopologyReplaceRejectsReparentingExistingWorktreeIdToDifferentRepo() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repository = fixture.repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000503")!
        let originalRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000211")!
        let replacementRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000212")!
        let reparentedWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000311")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Reparent Validation",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try repository.replaceRepositoryTopology(
            workspaceId: workspaceId,
            topology: .init(
                watchedPaths: [],
                repos: [
                    .init(
                        id: originalRepoId,
                        name: "original",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/original-repo"),
                        createdAt: Date(timeIntervalSince1970: 200),
                        worktrees: [
                            .init(
                                id: reparentedWorktreeId,
                                repoId: originalRepoId,
                                name: "original",
                                path: URL(fileURLWithPath: "/tmp/agentstudio/original-repo"),
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
            sourceRepoId: originalRepoId,
            sourceWorktreeId: reparentedWorktreeId
        )

        #expect(
            throws: WorkspaceCoreRepositoryError.worktreeRepoMismatch(
                worktreeId: reparentedWorktreeId,
                expectedRepoId: replacementRepoId,
                actualRepoId: originalRepoId
            )
        ) {
            try repository.replaceRepositoryTopology(
                workspaceId: workspaceId,
                topology: .init(
                    watchedPaths: [],
                    repos: [
                        .init(
                            id: replacementRepoId,
                            name: "replacement",
                            repoPath: URL(fileURLWithPath: "/tmp/agentstudio/replacement-repo"),
                            createdAt: Date(timeIntervalSince1970: 250),
                            worktrees: [
                                .init(
                                    id: reparentedWorktreeId,
                                    repoId: replacementRepoId,
                                    name: "replacement",
                                    path: URL(fileURLWithPath: "/tmp/agentstudio/replacement-repo"),
                                    isMainWorktree: true
                                )
                            ]
                        )
                    ],
                    unavailableRepoIds: []
                )
            )
        }
        let paneSource = try fixture.fetchPaneSource(paneId: paneId)

        #expect(paneSource?.repoId == originalRepoId)
        #expect(paneSource?.worktreeId == reparentedWorktreeId)
    }

    @Test("repository topology replace rejects duplicate repo ids")
    func repositoryTopologyReplaceRejectsDuplicateRepoIds() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000112")!
        let duplicateRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000213")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Duplicate Repos",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )

        #expect(throws: WorkspaceCoreRepositoryError.duplicateRepoId(duplicateRepoId)) {
            try repository.replaceRepositoryTopology(
                workspaceId: workspaceId,
                topology: .init(
                    watchedPaths: [],
                    repos: [
                        .init(
                            id: duplicateRepoId,
                            name: "first",
                            repoPath: URL(fileURLWithPath: "/tmp/agentstudio/duplicate-repo-first"),
                            createdAt: Date(timeIntervalSince1970: 200),
                            worktrees: []
                        ),
                        .init(
                            id: duplicateRepoId,
                            name: "second",
                            repoPath: URL(fileURLWithPath: "/tmp/agentstudio/duplicate-repo-second"),
                            createdAt: Date(timeIntervalSince1970: 250),
                            worktrees: []
                        ),
                    ],
                    unavailableRepoIds: []
                )
            )
        }
    }

    @Test("repository topology replace rejects duplicate worktree ids across repos")
    func repositoryTopologyReplaceRejectsDuplicateWorktreeIdsAcrossRepos() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000113")!
        let firstRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000214")!
        let secondRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000215")!
        let duplicateWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000312")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Duplicate Worktrees",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )

        #expect(throws: WorkspaceCoreRepositoryError.duplicateWorktreeId(duplicateWorktreeId)) {
            try repository.replaceRepositoryTopology(
                workspaceId: workspaceId,
                topology: .init(
                    watchedPaths: [],
                    repos: [
                        .init(
                            id: firstRepoId,
                            name: "first",
                            repoPath: URL(fileURLWithPath: "/tmp/agentstudio/duplicate-worktree-first"),
                            createdAt: Date(timeIntervalSince1970: 200),
                            worktrees: [
                                .init(
                                    id: duplicateWorktreeId,
                                    repoId: firstRepoId,
                                    name: "first",
                                    path: URL(fileURLWithPath: "/tmp/agentstudio/duplicate-worktree-first"),
                                    isMainWorktree: true
                                )
                            ]
                        ),
                        .init(
                            id: secondRepoId,
                            name: "second",
                            repoPath: URL(fileURLWithPath: "/tmp/agentstudio/duplicate-worktree-second"),
                            createdAt: Date(timeIntervalSince1970: 250),
                            worktrees: [
                                .init(
                                    id: duplicateWorktreeId,
                                    repoId: secondRepoId,
                                    name: "second",
                                    path: URL(fileURLWithPath: "/tmp/agentstudio/duplicate-worktree-second"),
                                    isMainWorktree: true
                                )
                            ]
                        ),
                    ],
                    unavailableRepoIds: []
                )
            )
        }
    }

    @Test("worktree reconciliation rejects duplicate worktree ids")
    func worktreeReconciliationRejectsDuplicateWorktreeIds() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000114")!
        let repoId = UUID(uuidString: "00000000-0000-0000-0000-000000000216")!
        let duplicateWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000313")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Duplicate Reconcile Worktrees",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try repository.replaceRepositoryTopology(
            workspaceId: workspaceId,
            topology: .init(
                watchedPaths: [],
                repos: [
                    .init(
                        id: repoId,
                        name: "repo",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/duplicate-reconcile-repo"),
                        createdAt: Date(timeIntervalSince1970: 200),
                        worktrees: []
                    )
                ],
                unavailableRepoIds: []
            )
        )

        #expect(throws: WorkspaceCoreRepositoryError.duplicateWorktreeId(duplicateWorktreeId)) {
            try repository.reconcileRepoWorktrees(
                workspaceId: workspaceId,
                repoId: repoId,
                worktrees: [
                    .init(
                        id: duplicateWorktreeId,
                        repoId: repoId,
                        name: "first",
                        path: URL(fileURLWithPath: "/tmp/agentstudio/duplicate-reconcile-first"),
                        isMainWorktree: true
                    ),
                    .init(
                        id: duplicateWorktreeId,
                        repoId: repoId,
                        name: "second",
                        path: URL(fileURLWithPath: "/tmp/agentstudio/duplicate-reconcile-second"),
                        isMainWorktree: false
                    ),
                ]
            )
        }
    }

}
