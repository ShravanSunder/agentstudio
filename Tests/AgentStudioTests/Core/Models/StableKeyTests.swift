import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class StableKeyTests {

    // MARK: - Determinism

    @Test

    func test_fromPath_samePathProducesSameKey() {
        // Arrange
        let url = URL(fileURLWithPath: "/tmp/test-repo")

        // Act
        let key1 = StableKey.fromPath(url)
        let key2 = StableKey.fromPath(url)

        // Assert
        #expect(key1 == key2)
    }

    // MARK: - Uniqueness

    @Test

    func test_fromPath_differentPathsProduceDifferentKeys() {
        // Arrange
        let url1 = URL(fileURLWithPath: "/tmp/repo-a")
        let url2 = URL(fileURLWithPath: "/tmp/repo-b")

        // Act
        let key1 = StableKey.fromPath(url1)
        let key2 = StableKey.fromPath(url2)

        // Assert
        #expect(key1 != key2)
    }

    // MARK: - Format

    @Test

    func test_fromPath_produces16HexChars() {
        // Arrange
        let url = URL(fileURLWithPath: "/tmp/test-repo")

        // Act
        let key = StableKey.fromPath(url)

        // Assert
        #expect(key.count == 16)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        #expect(key.unicodeScalars.allSatisfy { hexChars.contains($0) })
    }

    @Test

    func test_fromPath_producesLowercaseHex() {
        // Arrange
        let url = URL(fileURLWithPath: "/Users/Test/My Project")

        // Act
        let key = StableKey.fromPath(url)

        // Assert
        #expect(key == key.lowercased())
    }

    // MARK: - Symlink Resolution

    @Test

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
        #expect(keyFromReal == keyFromSymlink)
    }

    // MARK: - Repo/Worktree Integration

    @Test

    func test_repo_stableKey_matchesStableKeyFromPath() {
        // Arrange
        let repo = makeRepo(repoPath: "/tmp/test-repo")

        // Act
        let stableKey = repo.stableKey
        let fromPath = StableKey.fromPath(repo.repoPath)

        // Assert
        #expect(stableKey == fromPath)
    }

    @Test

    func test_worktree_stableKey_matchesStableKeyFromPath() {
        // Arrange
        let worktree = makeWorktree(path: "/tmp/test-repo/feature-branch")

        // Act
        let stableKey = worktree.stableKey
        let fromPath = StableKey.fromPath(worktree.path)

        // Assert
        #expect(stableKey == fromPath)
    }
}
