import XCTest

@testable import AgentStudio

final class WorktrunkParsingTests: XCTestCase {

    private let service = WorktrunkService.shared

    // MARK: - parseGitWorktreeList

    func test_parse_singleWorktree_withBranch() {
        // Arrange
        let output = "worktree /Users/dev/project/main\nHEAD abc123\nbranch refs/heads/main\n\n"

        // Act
        let result = service.parseGitWorktreeList(output)

        // Assert
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "main")
        XCTAssertEqual(result[0].branch, "main")
        XCTAssertEqual(result[0].path, URL(fileURLWithPath: "/Users/dev/project/main"))
    }

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
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "main")
        XCTAssertEqual(result[0].branch, "main")
        XCTAssertEqual(result[1].name, "feature-x")
        XCTAssertEqual(result[1].branch, "feature/feature-x")
    }

    func test_parse_noBranchLine_usesPathName() {
        // Arrange
        let output = "worktree /Users/dev/project/detached-head\nHEAD abc123\n\n"

        // Act
        let result = service.parseGitWorktreeList(output)

        // Assert
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "detached-head")
        XCTAssertEqual(result[0].branch, "detached-head")
    }

    func test_parse_emptyString_returnsEmpty() {
        // Act
        let result = service.parseGitWorktreeList("")

        // Assert
        XCTAssertTrue(result.isEmpty)
    }

    func test_parse_trailingNewlinesOnly_returnsEmpty() {
        // Act
        let result = service.parseGitWorktreeList("\n\n\n")

        // Assert
        XCTAssertTrue(result.isEmpty)
    }

    func test_parse_nestedBranch_stripsRefsHeads() {
        // Arrange
        let output = "worktree /Users/dev/project/sub-name\nbranch refs/heads/feature/sub/name\n\n"

        // Act
        let result = service.parseGitWorktreeList(output)

        // Assert
        XCTAssertEqual(result[0].branch, "feature/sub/name")
    }

    // MARK: - WorktrunkEntry JSON Parsing

    func test_worktrunkEntry_decodes_fullJSON() throws {
        // Arrange
        let json = """
            {"path": "/tmp/wt/main", "branch": "refs/heads/main", "head": "abc123", "status": "clean"}
            """
        let data = json.data(using: .utf8)!

        // Act
        let entry = try JSONDecoder().decode(WorktrunkEntry.self, from: data)

        // Assert
        XCTAssertEqual(entry.path, "/tmp/wt/main")
        XCTAssertEqual(entry.branch, "refs/heads/main")
        XCTAssertEqual(entry.head, "abc123")
        XCTAssertEqual(entry.status, "clean")
    }

    func test_worktrunkEntry_decodes_minimalJSON() throws {
        // Arrange
        let json = """
            {"path": "/tmp/wt/feat", "branch": "refs/heads/feat"}
            """
        let data = json.data(using: .utf8)!

        // Act
        let entry = try JSONDecoder().decode(WorktrunkEntry.self, from: data)

        // Assert
        XCTAssertEqual(entry.path, "/tmp/wt/feat")
        XCTAssertNil(entry.head)
        XCTAssertNil(entry.status)
    }

    // MARK: - WorktrunkError

    func test_worktrunkError_descriptions_nonEmpty() {
        // Arrange
        let errors: [WorktrunkError] = [
            .commandFailed("git error"),
            .worktreeNotFound,
            .notAGitRepository,
        ]

        // Assert
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    func test_worktrunkError_commandFailed_includesMessage() {
        // Arrange
        let error = WorktrunkError.commandFailed("fatal: not a repo")

        // Assert
        XCTAssertTrue(error.errorDescription!.contains("fatal: not a repo"))
    }

    func test_worktrunkError_conformsToLocalizedError() {
        // Arrange
        let error: LocalizedError = WorktrunkError.worktreeNotFound

        // Assert
        XCTAssertNotNil(error.errorDescription)
    }
}
