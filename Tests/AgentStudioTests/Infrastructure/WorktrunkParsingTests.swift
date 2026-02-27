import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct WorktrunkParsingTests {

    private let service = WorktrunkService.shared

    // MARK: - parseGitWorktreeList

    @Test
    func test_parse_singleWorktree_withBranch() {
        // Arrange
        let output = "worktree /Users/dev/project/main\nHEAD abc123\nbranch refs/heads/main\n\n"

        // Act
        let result = service.parseGitWorktreeList(output)

        // Assert
        #expect(result.count == 1)
        #expect(result[0].name == "main")
        #expect(result[0].branch == "main")
        #expect(result[0].path == URL(fileURLWithPath: "/Users/dev/project/main"))
    }

    @Test
    func test_parse_multipleWorktrees() {
        // Arrange
        let output = """
            worktree /Users/dev/project/main
            HEAD abc123
            branch refs/heads/main

            worktree /Users/dev/project/feature-x
            HEAD def456
            branch refs/heads/feature/feature-x

            """

        // Act
        let result = service.parseGitWorktreeList(output)

        // Assert
        #expect(result.count == 2)
        #expect(result[0].name == "main")
        #expect(result[0].branch == "main")
        #expect(result[1].name == "feature-x")
        #expect(result[1].branch == "feature/feature-x")
    }

    @Test
    func test_parse_noBranchLine_usesPathName() {
        // Arrange
        let output = "worktree /Users/dev/project/detached-head\nHEAD abc123\n\n"

        // Act
        let result = service.parseGitWorktreeList(output)

        // Assert
        #expect(result.count == 1)
        #expect(result[0].name == "detached-head")
        #expect(result[0].branch == "detached-head")
    }

    @Test
    func test_parse_emptyString_returnsEmpty() {
        // Act
        let result = service.parseGitWorktreeList("")

        // Assert
        #expect(result.isEmpty)
    }

    @Test
    func test_parse_trailingNewlinesOnly_returnsEmpty() {
        // Act
        let result = service.parseGitWorktreeList("\n\n\n")

        // Assert
        #expect(result.isEmpty)
    }

    @Test
    func test_parse_nestedBranch_stripsRefsHeads() {
        // Arrange
        let output = "worktree /Users/dev/project/sub-name\nbranch refs/heads/feature/sub/name\n\n"

        // Act
        let result = service.parseGitWorktreeList(output)

        // Assert
        #expect(result[0].branch == "feature/sub/name")
    }

    // MARK: - WorktrunkEntry JSON Parsing

    @Test
    func test_worktrunkEntry_decodes_fullJSON() throws {
        // Arrange
        let json = """
            {"path": "/tmp/wt/main", "branch": "refs/heads/main", "head": "abc123", "status": "clean"}
            """
        let data = json.data(using: .utf8)!

        // Act
        let entry = try JSONDecoder().decode(WorktrunkEntry.self, from: data)

        // Assert
        #expect(entry.path == "/tmp/wt/main")
        #expect(entry.branch == "refs/heads/main")
        #expect(entry.head == "abc123")
        #expect(entry.status == "clean")
    }

    @Test
    func test_worktrunkEntry_decodes_minimalJSON() throws {
        // Arrange
        let json = """
            {"path": "/tmp/wt/feat", "branch": "refs/heads/feat"}
            """
        let data = json.data(using: .utf8)!

        // Act
        let entry = try JSONDecoder().decode(WorktrunkEntry.self, from: data)

        // Assert
        #expect(entry.path == "/tmp/wt/feat")
        #expect(entry.head == nil)
        #expect(entry.status == nil)
    }

    // MARK: - Worktrunk/Git Merge

    @Test
    func test_mergeWorktrunkEntries_matchesByCanonicalPathOnly() {
        // Arrange
        let entries: [WorktrunkEntry] = [
            .init(path: "/tmp/askluna-finance/main", branch: "refs/heads/main", head: nil, status: nil),
            .init(path: "/tmp/askluna-finance/feature-a", branch: "refs/heads/feature-a", head: nil, status: nil),
            .init(path: "/tmp/askluna-finance-archive/main", branch: "refs/heads/archive-main", head: nil, status: nil),
        ]
        let gitWorktrees: [Worktree] = [
            Worktree(
                name: "main", path: URL(fileURLWithPath: "/tmp/askluna-finance/main"), branch: "main",
                isMainWorktree: true),
            Worktree(
                name: "feature-a",
                path: URL(fileURLWithPath: "/tmp/askluna-finance/feature-a"),
                branch: "feature-a",
                isMainWorktree: false
            ),
        ]

        // Act
        let merged = service.mergeWorktrunkEntries(entries, orderedBy: gitWorktrees)

        // Assert
        #expect(merged.count == 2)
        #expect(merged[0].path.path == "/tmp/askluna-finance/main")
        #expect(merged[0].branch == "main")
        #expect(merged[1].path.path == "/tmp/askluna-finance/feature-a")
        #expect(merged[1].branch == "feature-a")
    }

    @Test
    func test_mergeWorktrunkEntries_preservesGitOrderAndFallsBackWhenMissingEntry() {
        // Arrange
        let entries: [WorktrunkEntry] = [
            .init(path: "/tmp/repo/feature-b", branch: "refs/heads/feature-b", head: nil, status: nil)
        ]
        let gitWorktrees: [Worktree] = [
            Worktree(name: "main", path: URL(fileURLWithPath: "/tmp/repo/main"), branch: "main", isMainWorktree: true),
            Worktree(name: "feature-b", path: URL(fileURLWithPath: "/tmp/repo/feature-b"), branch: "feature-b"),
        ]

        // Act
        let merged = service.mergeWorktrunkEntries(entries, orderedBy: gitWorktrees)

        // Assert
        #expect(merged.count == 2)
        #expect(merged[0].name == "main")
        #expect(merged[0].branch == "main")
        #expect(merged[0].isMainWorktree == true)
        #expect(merged[1].name == "feature-b")
        #expect(merged[1].branch == "feature-b")
        #expect(merged[1].isMainWorktree == false)
    }

    // MARK: - WorktrunkError

    @Test
    func test_worktrunkError_descriptions_nonEmpty() {
        // Arrange
        let errors: [WorktrunkError] = [
            .commandFailed("git error"),
            .worktreeNotFound,
            .notAGitRepository,
        ]

        // Assert
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test
    func test_worktrunkError_commandFailed_includesMessage() {
        // Arrange
        let error = WorktrunkError.commandFailed("fatal: not a repo")

        // Assert
        #expect(error.errorDescription?.contains("fatal: not a repo") == true)
    }

    @Test
    func test_worktrunkError_conformsToLocalizedError() {
        // Arrange
        let error: LocalizedError = WorktrunkError.worktreeNotFound

        // Assert
        #expect(error.errorDescription != nil)
    }
}
