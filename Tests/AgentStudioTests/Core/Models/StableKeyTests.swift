import XCTest

@testable import AgentStudio

final class StableKeyTests: XCTestCase {

    // MARK: - Determinism

    func test_fromPath_samePathProducesSameKey() {
        // Arrange
        let url = URL(fileURLWithPath: "/tmp/test-repo")

        // Act
        let key1 = StableKey.fromPath(url)
        let key2 = StableKey.fromPath(url)

        // Assert
        XCTAssertEqual(key1, key2)
    }

    // MARK: - Uniqueness

    func test_fromPath_differentPathsProduceDifferentKeys() {
        // Arrange
        let url1 = URL(fileURLWithPath: "/tmp/repo-a")
        let url2 = URL(fileURLWithPath: "/tmp/repo-b")

        // Act
        let key1 = StableKey.fromPath(url1)
        let key2 = StableKey.fromPath(url2)

        // Assert
        XCTAssertNotEqual(key1, key2)
    }

    // MARK: - Format

    func test_fromPath_produces16HexChars() {
        // Arrange
        let url = URL(fileURLWithPath: "/tmp/test-repo")

        // Act
        let key = StableKey.fromPath(url)

        // Assert
        XCTAssertEqual(key.count, 16)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(key.unicodeScalars.allSatisfy { hexChars.contains($0) })
    }

    func test_fromPath_producesLowercaseHex() {
        // Arrange
        let url = URL(fileURLWithPath: "/Users/Test/My Project")

        // Act
        let key = StableKey.fromPath(url)

        // Assert
        XCTAssertEqual(key, key.lowercased())
    }

    // MARK: - Symlink Resolution

    func test_fromPath_resolvesSymlinks() throws {
        // Arrange — create a temp directory and a symlink to it
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stablekey-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let symlinkDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stablekey-symlink-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: symlinkDir, withDestinationURL: tempDir)
        defer { try? FileManager.default.removeItem(at: symlinkDir) }

        // Act
        let keyFromReal = StableKey.fromPath(tempDir)
        let keyFromSymlink = StableKey.fromPath(symlinkDir)

        // Assert — both should resolve to the same key
        XCTAssertEqual(keyFromReal, keyFromSymlink)
    }

    // MARK: - Repo/Worktree Integration

    func test_repo_stableKey_matchesStableKeyFromPath() {
        // Arrange
        let repo = makeRepo(repoPath: "/tmp/test-repo")

        // Act
        let stableKey = repo.stableKey
        let fromPath = StableKey.fromPath(repo.repoPath)

        // Assert
        XCTAssertEqual(stableKey, fromPath)
    }

    func test_worktree_stableKey_matchesStableKeyFromPath() {
        // Arrange
        let worktree = makeWorktree(path: "/tmp/test-repo/feature-branch")

        // Act
        let stableKey = worktree.stableKey
        let fromPath = StableKey.fromPath(worktree.path)

        // Assert
        XCTAssertEqual(stableKey, fromPath)
    }
}
