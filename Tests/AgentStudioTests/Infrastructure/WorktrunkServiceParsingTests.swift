import Foundation
import Testing

@testable import AgentStudio

@Suite("WorktrunkService parsing")
struct WorktrunkServiceParsingTests {

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
        let worktrees = service.parseGitWorktreeList(output)

        // Assert
        #expect(worktrees.count == 2)
        #expect(worktrees[0].isMainWorktree == true)
        #expect(worktrees[0].branch == "main")
        #expect(worktrees[1].isMainWorktree == false)
        #expect(worktrees[1].branch == "feature-branch")
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
        let worktrees = service.parseGitWorktreeList(output)

        // Assert
        #expect(worktrees.count == 1)
        #expect(worktrees[0].isMainWorktree == true)
    }

    @Test("parseGitWorktreeList empty output returns empty")
    func emptyOutput() {
        // Arrange & Act
        let worktrees = WorktrunkService.shared.parseGitWorktreeList("")

        // Assert
        #expect(worktrees.isEmpty)
    }

    @Test("isMainWorktree defaults to false when decoding legacy data")
    func legacyDecodingDefaultsFalse() throws {
        // Arrange — JSON without isMainWorktree key
        let json = """
            {
                "id": "00000000-0000-0000-0000-000000000001",
                "name": "test",
                "path": "file:///tmp/test",
                "branch": "main",
                "status": "idle"
            }
            """
        let data = json.data(using: .utf8)!

        // Act
        let worktree = try JSONDecoder().decode(Worktree.self, from: data)

        // Assert
        #expect(worktree.isMainWorktree == false)
    }
}
