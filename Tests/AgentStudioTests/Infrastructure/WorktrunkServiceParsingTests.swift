import Foundation
import Testing

@testable import AgentStudio

@Suite("WorktrunkService parsing")
struct WorktrunkServiceParsingTests {

    private let testRepoId = UUID()

    @Test("parseGitWorktreeList marks first entry as main worktree")
    func firstEntryIsMain() {
        // Arrange
        let output = """
            worktree /path/to/repo
            HEAD abc1234
            branch refs/heads/main

            worktree /path/to/repo-feature
            HEAD def5678
            branch refs/heads/feature-branch

            """
        let service = WorktrunkService.shared

        // Act
        let worktrees = service.parseGitWorktreeList(output, repoId: testRepoId)

        // Assert
        #expect(worktrees.count == 2)
        #expect(worktrees[0].isMainWorktree == true)
        #expect(worktrees[0].repoId == testRepoId)
        #expect(worktrees[1].isMainWorktree == false)
        #expect(worktrees[1].repoId == testRepoId)
    }

    @Test("parseGitWorktreeList single entry is main")
    func singleEntryIsMain() {
        // Arrange
        let output = """
            worktree /path/to/repo
            HEAD abc1234
            branch refs/heads/main

            """
        let service = WorktrunkService.shared

        // Act
        let worktrees = service.parseGitWorktreeList(output, repoId: testRepoId)

        // Assert
        #expect(worktrees.count == 1)
        #expect(worktrees[0].isMainWorktree == true)
    }

    @Test("parseGitWorktreeList empty output returns empty")
    func emptyOutput() {
        // Arrange & Act
        let worktrees = WorktrunkService.shared.parseGitWorktreeList("", repoId: testRepoId)

        // Assert
        #expect(worktrees.isEmpty)
    }

    @Test("missing isMainWorktree throws DecodingError")
    func missingIsMainWorktreeThrows() throws {
        // Arrange — JSON with repoId but without isMainWorktree key
        let json = """
            {
                "id": "00000000-0000-0000-0000-000000000001",
                "repoId": "\(testRepoId.uuidString)",
                "name": "test",
                "path": "file:///tmp/test"
            }
            """
        let data = json.data(using: .utf8)!

        // Act & Assert — strict decode rejects missing isMainWorktree
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Worktree.self, from: data)
        }
    }
}
