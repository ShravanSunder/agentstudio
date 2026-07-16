import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace topology preparation")
struct WorkspaceTopologyPreparerTests {
    @Test("preparation preserves repository and worktree identity without MainActor state")
    func preparationPreservesRepositoryAndWorktreeIdentity() throws {
        // Arrange
        let workspaceID = UUIDv7.generate()
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let watchedPath = WatchedPath(path: URL(filePath: "/tmp/topology-preparer-watch"))
        let snapshot = RepositoryTopologySQLiteSnapshot(
            id: workspaceID,
            repos: [
                CanonicalRepo(
                    id: repositoryID,
                    name: "agent-studio",
                    repoPath: URL(filePath: "/tmp/agent-studio")
                )
            ],
            worktrees: [
                CanonicalWorktree(
                    id: worktreeID,
                    repoId: repositoryID,
                    name: "main",
                    path: URL(filePath: "/tmp/agent-studio"),
                    isMainWorktree: true
                )
            ],
            watchedPaths: [watchedPath],
            updatedAt: Date(timeIntervalSince1970: 1)
        )

        // Act
        let result = WorkspaceTopologyPreparer.prepare(snapshot)

        // Assert
        guard case .prepared(let prepared) = result else {
            Issue.record("expected valid topology preparation")
            return
        }
        #expect(prepared.workspaceID == workspaceID)
        #expect(prepared.replacement.repositories.map(\.id) == [repositoryID])
        #expect(prepared.replacement.repositories.first?.worktrees.map(\.id) == [worktreeID])
        #expect(prepared.replacement.watchedPaths.map(\.id) == [watchedPath.id])
    }

    @Test("preparation rejects a worktree whose repository is absent")
    func preparationRejectsOrphanedWorktree() {
        // Arrange
        let worktreeID = UUIDv7.generate()
        let missingRepositoryID = UUIDv7.generate()
        let snapshot = RepositoryTopologySQLiteSnapshot(
            id: UUIDv7.generate(),
            worktrees: [
                CanonicalWorktree(
                    id: worktreeID,
                    repoId: missingRepositoryID,
                    name: "orphan",
                    path: URL(filePath: "/tmp/orphan"),
                    isMainWorktree: false
                )
            ],
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        // Act
        let result = WorkspaceTopologyPreparer.prepare(snapshot)

        // Assert
        guard case .rejected(let rejection) = result else {
            Issue.record("expected orphaned worktree rejection")
            return
        }
        #expect(
            rejection
                == .worktreeRepositoryMissing(
                    worktreeID: worktreeID,
                    repositoryID: missingRepositoryID
                )
        )
    }

    @Test("preparation rejects duplicate repository identity")
    func preparationRejectsDuplicateRepositoryIdentity() {
        // Arrange
        let repositoryID = UUIDv7.generate()
        let snapshot = RepositoryTopologySQLiteSnapshot(
            id: UUIDv7.generate(),
            repos: [
                CanonicalRepo(
                    id: repositoryID,
                    name: "first",
                    repoPath: URL(filePath: "/tmp/first")
                ),
                CanonicalRepo(
                    id: repositoryID,
                    name: "second",
                    repoPath: URL(filePath: "/tmp/second")
                ),
            ],
            updatedAt: Date(timeIntervalSince1970: 3)
        )

        // Act
        let result = WorkspaceTopologyPreparer.prepare(snapshot)

        // Assert
        guard case .rejected(let rejection) = result else {
            Issue.record("expected duplicate repository rejection")
            return
        }
        #expect(rejection == .invalidIdentity(.duplicateRepositoryID(repositoryID)))
    }
}
