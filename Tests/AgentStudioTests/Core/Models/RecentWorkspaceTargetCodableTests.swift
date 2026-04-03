import Foundation
import Testing

@testable import AgentStudio

@Suite
struct RecentWorkspaceTargetCodableTests {

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Round-trip tests

    @Test
    func roundTrip_worktreeTarget_preservesAllFields() throws {
        // Arrange
        let repoId = UUID()
        let worktreeId = UUID()
        let repo = Repo(
            id: repoId,
            name: "my-repo",
            repoPath: URL(fileURLWithPath: "/repos/my-repo"),
            worktrees: [
                Worktree(id: worktreeId, repoId: repoId, name: "main", path: URL(fileURLWithPath: "/repos/my-repo"))
            ]
        )
        let worktree = repo.worktrees[0]
        let original = RecentWorkspaceTarget.forWorktree(
            path: URL(fileURLWithPath: "/repos/my-repo"),
            worktree: worktree,
            repo: repo,
            displayTitle: "my-repo",
            subtitle: "main branch"
        )

        // Act
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(RecentWorkspaceTarget.self, from: data)

        // Assert
        #expect(decoded.id == original.id)
        #expect(decoded.path == original.path)
        #expect(decoded.displayTitle == original.displayTitle)
        #expect(decoded.subtitle == original.subtitle)
        #expect(decoded.repoId == repoId)
        #expect(decoded.worktreeId == worktreeId)
        #expect(decoded.kind == .worktree)
    }

    @Test
    func roundTrip_cwdOnlyTarget_preservesAllFields() throws {
        // Arrange
        let original = RecentWorkspaceTarget.forCwd(
            URL(fileURLWithPath: "/tmp/scratch"),
            title: "Scratch",
            subtitle: "/tmp/scratch"
        )

        // Act
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(RecentWorkspaceTarget.self, from: data)

        // Assert
        #expect(decoded.id == original.id)
        #expect(decoded.path == original.path)
        #expect(decoded.displayTitle == "Scratch")
        #expect(decoded.repoId == nil)
        #expect(decoded.worktreeId == nil)
        #expect(decoded.kind == .cwdOnly)
    }

    // MARK: - Decode validation tests

    @Test
    func decode_worktreeTarget_missingRepoId_throws() throws {
        // Arrange: worktree kind but no repoId
        let json = """
            {
                "id": "worktree:00000000-0000-0000-0000-000000000001",
                "path": "file:///repos/my-repo",
                "displayTitle": "my-repo",
                "subtitle": "main",
                "worktreeId": "00000000-0000-0000-0000-000000000002",
                "kind": "worktree",
                "lastOpenedAt": "2026-04-01T00:00:00Z"
            }
            """

        // Act / Assert
        #expect(throws: DecodingError.self) {
            try decoder.decode(RecentWorkspaceTarget.self, from: Data(json.utf8))
        }
    }

    @Test
    func decode_worktreeTarget_missingWorktreeId_throws() throws {
        // Arrange: worktree kind but no worktreeId
        let json = """
            {
                "id": "worktree:00000000-0000-0000-0000-000000000001",
                "path": "file:///repos/my-repo",
                "displayTitle": "my-repo",
                "subtitle": "main",
                "repoId": "00000000-0000-0000-0000-000000000001",
                "kind": "worktree",
                "lastOpenedAt": "2026-04-01T00:00:00Z"
            }
            """

        // Act / Assert
        #expect(throws: DecodingError.self) {
            try decoder.decode(RecentWorkspaceTarget.self, from: Data(json.utf8))
        }
    }

    @Test
    func decode_cwdOnlyTarget_withRepoId_throws() throws {
        // Arrange: cwdOnly kind but has repoId (violates invariant)
        let json = """
            {
                "id": "cwd:/tmp/scratch",
                "path": "file:///tmp/scratch",
                "displayTitle": "Scratch",
                "subtitle": "/tmp/scratch",
                "repoId": "00000000-0000-0000-0000-000000000001",
                "kind": "cwdOnly",
                "lastOpenedAt": "2026-04-01T00:00:00Z"
            }
            """

        // Act / Assert
        #expect(throws: DecodingError.self) {
            try decoder.decode(RecentWorkspaceTarget.self, from: Data(json.utf8))
        }
    }

    @Test
    func decode_cwdOnlyTarget_withWorktreeId_throws() throws {
        // Arrange: cwdOnly kind but has worktreeId (violates invariant)
        let json = """
            {
                "id": "cwd:/tmp/scratch",
                "path": "file:///tmp/scratch",
                "displayTitle": "Scratch",
                "subtitle": "/tmp/scratch",
                "worktreeId": "00000000-0000-0000-0000-000000000002",
                "kind": "cwdOnly",
                "lastOpenedAt": "2026-04-01T00:00:00Z"
            }
            """

        // Act / Assert
        #expect(throws: DecodingError.self) {
            try decoder.decode(RecentWorkspaceTarget.self, from: Data(json.utf8))
        }
    }

    // MARK: - Factory edge cases

    @Test
    func forCwd_nilTitle_fallsToPathLastComponent() {
        let target = RecentWorkspaceTarget.forCwd(
            URL(fileURLWithPath: "/Users/dev/my-project"),
            title: nil
        )

        #expect(target.displayTitle == "my-project")
        #expect(target.kind == .cwdOnly)
    }

    @Test
    func forCwd_emptyTitle_fallsToPathLastComponent() {
        let target = RecentWorkspaceTarget.forCwd(
            URL(fileURLWithPath: "/Users/dev/my-project"),
            title: "   "
        )

        #expect(target.displayTitle == "my-project")
    }

    @Test
    func decode_missingSubtitle_fallsBackToPath() throws {
        // Arrange: valid worktree JSON with no subtitle field
        let json = """
            {
                "id": "worktree:00000000-0000-0000-0000-000000000001",
                "path": "file:///repos/my-repo",
                "displayTitle": "my-repo",
                "repoId": "00000000-0000-0000-0000-000000000001",
                "worktreeId": "00000000-0000-0000-0000-000000000002",
                "kind": "worktree",
                "lastOpenedAt": "2026-04-01T00:00:00Z"
            }
            """

        // Act
        let decoded = try decoder.decode(RecentWorkspaceTarget.self, from: Data(json.utf8))

        // Assert: subtitle falls back to path
        #expect(decoded.subtitle == decoded.path.path)
    }
}
