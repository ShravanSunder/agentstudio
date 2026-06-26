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

    @Test("repository topology replace rejects duplicate watched path stable keys")
    func repositoryTopologyReplaceRejectsDuplicateWatchedPathStableKeys() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000121")!
        let duplicateStableKey = "duplicate-watch-key"
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Duplicate Watch Stable Keys",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )

        #expect(throws: WorkspaceCoreRepositoryError.duplicateWatchedPathStableKey(duplicateStableKey)) {
            try repository.replaceRepositoryTopology(
                workspaceId: workspaceId,
                topology: .init(
                    watchedPaths: [
                        .init(
                            id: UUID(uuidString: "00000000-0000-0000-0000-000000000403")!,
                            path: URL(fileURLWithPath: "/tmp/agentstudio/duplicate-watch-a"),
                            stableKey: duplicateStableKey,
                            addedAt: Date(timeIntervalSince1970: 200)
                        ),
                        .init(
                            id: UUID(uuidString: "00000000-0000-0000-0000-000000000404")!,
                            path: URL(fileURLWithPath: "/tmp/agentstudio/duplicate-watch-b"),
                            stableKey: duplicateStableKey,
                            addedAt: Date(timeIntervalSince1970: 250)
                        ),
                    ],
                    repos: [],
                    unavailableRepoIds: []
                )
            )
        }
    }

    @Test("repository topology replace rejects duplicate repo stable keys")
    func repositoryTopologyReplaceRejectsDuplicateRepoStableKeys() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000122")!
        let duplicateStableKey = "duplicate-repo-key"
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Duplicate Repo Stable Keys",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )

        #expect(throws: WorkspaceCoreRepositoryError.duplicateRepoStableKey(duplicateStableKey)) {
            try repository.replaceRepositoryTopology(
                workspaceId: workspaceId,
                topology: .init(
                    watchedPaths: [],
                    repos: [
                        .init(
                            id: UUID(uuidString: "00000000-0000-0000-0000-000000000226")!,
                            name: "first",
                            repoPath: URL(fileURLWithPath: "/tmp/agentstudio/duplicate-repo-stable-a"),
                            stableKey: duplicateStableKey,
                            createdAt: Date(timeIntervalSince1970: 200),
                            worktrees: []
                        ),
                        .init(
                            id: UUID(uuidString: "00000000-0000-0000-0000-000000000227")!,
                            name: "second",
                            repoPath: URL(fileURLWithPath: "/tmp/agentstudio/duplicate-repo-stable-b"),
                            stableKey: duplicateStableKey,
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

    @Test("repository topology replace rejects duplicate worktree stable keys across repos")
    func repositoryTopologyReplaceRejectsDuplicateWorktreeStableKeysAcrossRepos() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let firstRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000228")!
        let secondRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000229")!
        let duplicateStableKey = "duplicate-worktree-key"
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Duplicate Worktree Stable Keys",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )

        #expect(throws: WorkspaceCoreRepositoryError.duplicateWorktreeStableKey(duplicateStableKey)) {
            try repository.replaceRepositoryTopology(
                workspaceId: workspaceId,
                topology: .init(
                    watchedPaths: [],
                    repos: [
                        .init(
                            id: firstRepoId,
                            name: "first",
                            repoPath: URL(fileURLWithPath: "/tmp/agentstudio/duplicate-worktree-stable-first"),
                            createdAt: Date(timeIntervalSince1970: 200),
                            worktrees: [
                                .init(
                                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000322")!,
                                    repoId: firstRepoId,
                                    name: "first",
                                    path: URL(
                                        fileURLWithPath: "/tmp/agentstudio/duplicate-worktree-stable-first"
                                    ),
                                    stableKey: duplicateStableKey,
                                    isMainWorktree: true
                                )
                            ]
                        ),
                        .init(
                            id: secondRepoId,
                            name: "second",
                            repoPath: URL(fileURLWithPath: "/tmp/agentstudio/duplicate-worktree-stable-second"),
                            createdAt: Date(timeIntervalSince1970: 250),
                            worktrees: [
                                .init(
                                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000323")!,
                                    repoId: secondRepoId,
                                    name: "second",
                                    path: URL(
                                        fileURLWithPath: "/tmp/agentstudio/duplicate-worktree-stable-second"
                                    ),
                                    stableKey: duplicateStableKey,
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

    @Test("worktree reconciliation rejects duplicate worktree stable keys")
    func worktreeReconciliationRejectsDuplicateWorktreeStableKeys() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000124")!
        let repoId = UUID(uuidString: "00000000-0000-0000-0000-000000000230")!
        let duplicateStableKey = "duplicate-reconcile-worktree-key"
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Duplicate Reconcile Worktree Stable Keys",
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
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/duplicate-reconcile-stable-repo"),
                        createdAt: Date(timeIntervalSince1970: 200),
                        worktrees: []
                    )
                ],
                unavailableRepoIds: []
            )
        )

        #expect(throws: WorkspaceCoreRepositoryError.duplicateWorktreeStableKey(duplicateStableKey)) {
            try repository.reconcileRepoWorktrees(
                workspaceId: workspaceId,
                repoId: repoId,
                worktrees: [
                    .init(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000324")!,
                        repoId: repoId,
                        name: "first",
                        path: URL(fileURLWithPath: "/tmp/agentstudio/duplicate-reconcile-stable-first"),
                        stableKey: duplicateStableKey,
                        isMainWorktree: true
                    ),
                    .init(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000325")!,
                        repoId: repoId,
                        name: "second",
                        path: URL(fileURLWithPath: "/tmp/agentstudio/duplicate-reconcile-stable-second"),
                        stableKey: duplicateStableKey,
                        isMainWorktree: false
                    ),
                ]
            )
        }
    }

    @Test("worktree reconciliation rejects stable key already owned by another repo")
    func worktreeReconciliationRejectsStableKeyAlreadyOwnedByAnotherRepo() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000125")!
        let targetRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000231")!
        let otherRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000232")!
        let collidingStableKey = "foreign-repo-worktree-key"
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Foreign Stable Key",
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
                        id: targetRepoId,
                        name: "target",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/foreign-stable-key-target"),
                        createdAt: Date(timeIntervalSince1970: 200),
                        worktrees: []
                    ),
                    .init(
                        id: otherRepoId,
                        name: "other",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/foreign-stable-key-other"),
                        createdAt: Date(timeIntervalSince1970: 250),
                        worktrees: [
                            .init(
                                id: UUID(uuidString: "00000000-0000-0000-0000-000000000326")!,
                                repoId: otherRepoId,
                                name: "other",
                                path: URL(fileURLWithPath: "/tmp/agentstudio/foreign-stable-key-other"),
                                stableKey: collidingStableKey,
                                isMainWorktree: true
                            )
                        ]
                    ),
                ],
                unavailableRepoIds: []
            )
        )

        #expect(throws: WorkspaceCoreRepositoryError.duplicateWorktreeStableKey(collidingStableKey)) {
            try repository.reconcileRepoWorktrees(
                workspaceId: workspaceId,
                repoId: targetRepoId,
                worktrees: [
                    .init(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000327")!,
                        repoId: targetRepoId,
                        name: "target",
                        path: URL(fileURLWithPath: "/tmp/agentstudio/foreign-stable-key-target"),
                        stableKey: collidingStableKey,
                        isMainWorktree: true
                    )
                ]
            )
        }
    }

    @Test("worktree reconciliation rejects worktree id owned by another workspace")
    func worktreeReconciliationRejectsWorktreeIdOwnedByAnotherWorkspace() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000126")!
        let otherWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000127")!
        let targetRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000233")!
        let otherRepoId = UUID(uuidString: "00000000-0000-0000-0000-000000000234")!
        let foreignWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000328")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Target Workspace",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try repository.upsertWorkspace(
            .init(
                id: otherWorkspaceId,
                name: "Other Workspace",
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
                        id: targetRepoId,
                        name: "target",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/foreign-worktree-target"),
                        createdAt: Date(timeIntervalSince1970: 200),
                        worktrees: []
                    )
                ],
                unavailableRepoIds: []
            )
        )
        try repository.replaceRepositoryTopology(
            workspaceId: otherWorkspaceId,
            topology: .init(
                watchedPaths: [],
                repos: [
                    .init(
                        id: otherRepoId,
                        name: "other",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/foreign-worktree-other"),
                        createdAt: Date(timeIntervalSince1970: 250),
                        worktrees: [
                            .init(
                                id: foreignWorktreeId,
                                repoId: otherRepoId,
                                name: "other",
                                path: URL(fileURLWithPath: "/tmp/agentstudio/foreign-worktree-other"),
                                isMainWorktree: true
                            )
                        ]
                    )
                ],
                unavailableRepoIds: []
            )
        )

        #expect(
            throws: WorkspaceCoreRepositoryError.worktreeBelongsToDifferentWorkspace(
                worktreeId: foreignWorktreeId,
                expectedWorkspaceId: workspaceId,
                actualWorkspaceId: otherWorkspaceId
            )
        ) {
            try repository.reconcileRepoWorktrees(
                workspaceId: workspaceId,
                repoId: targetRepoId,
                worktrees: [
                    .init(
                        id: foreignWorktreeId,
                        repoId: targetRepoId,
                        name: "target",
                        path: URL(fileURLWithPath: "/tmp/agentstudio/foreign-worktree-target"),
                        isMainWorktree: true
                    )
                ]
            )
        }
    }

    @Test("repository topology replace rejects invalid repository tags")
    func repositoryTopologyReplaceRejectsInvalidRepositoryTags() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000129")!
        let repoId = UUID(uuidString: "00000000-0000-0000-0000-000000000236")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Invalid Repo Tags",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )

        #expect(throws: WorkspaceCoreRepositoryError.invalidRepositoryTag(" leading")) {
            try repository.replaceRepositoryTopology(
                workspaceId: workspaceId,
                topology: .init(
                    watchedPaths: [],
                    repos: [
                        .init(
                            id: repoId,
                            name: "repo",
                            repoPath: URL(fileURLWithPath: "/tmp/agentstudio/invalid-repo-tag"),
                            createdAt: Date(timeIntervalSince1970: 200),
                            worktrees: [],
                            tags: [" leading"]
                        )
                    ],
                    unavailableRepoIds: []
                )
            )
        }
        #expect(throws: WorkspaceCoreRepositoryError.invalidRepositoryTag("spoof\u{2066}tag")) {
            try repository.replaceRepositoryTopology(
                workspaceId: workspaceId,
                topology: .init(
                    watchedPaths: [],
                    repos: [
                        .init(
                            id: repoId,
                            name: "repo",
                            repoPath: URL(fileURLWithPath: "/tmp/agentstudio/invalid-repo-tag"),
                            createdAt: Date(timeIntervalSince1970: 200),
                            worktrees: [],
                            tags: ["spoof\u{2066}tag"]
                        )
                    ],
                    unavailableRepoIds: []
                )
            )
        }
    }

    @Test("repository topology replace rejects duplicate worktree tags")
    func repositoryTopologyReplaceRejectsDuplicateWorktreeTags() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000130")!
        let repoId = UUID(uuidString: "00000000-0000-0000-0000-000000000237")!
        let worktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000330")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Duplicate Worktree Tags",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )

        #expect(throws: WorkspaceCoreRepositoryError.duplicateRepositoryTag("wip")) {
            try repository.replaceRepositoryTopology(
                workspaceId: workspaceId,
                topology: .init(
                    watchedPaths: [],
                    repos: [
                        .init(
                            id: repoId,
                            name: "repo",
                            repoPath: URL(fileURLWithPath: "/tmp/agentstudio/duplicate-worktree-tag"),
                            createdAt: Date(timeIntervalSince1970: 200),
                            worktrees: [
                                .init(
                                    id: worktreeId,
                                    repoId: repoId,
                                    name: "main",
                                    path: URL(fileURLWithPath: "/tmp/agentstudio/duplicate-worktree-tag"),
                                    isMainWorktree: true,
                                    tags: ["wip", "wip"]
                                )
                            ]
                        )
                    ],
                    unavailableRepoIds: []
                )
            )
        }
    }

}
