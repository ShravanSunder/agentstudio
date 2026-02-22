import Foundation
import Testing

@testable import AgentStudio

@Suite("RepoScanner")
struct RepoScannerTests {

    @Test("discovers git repos up to 3 levels deep")
    func discoversReposAtDepth() throws {
        // Arrange
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "scanner-test-\(UUID().uuidString)")
        let fm = FileManager.default

        // Level 1: repo-a/.git
        try fm.createDirectory(
            at: tmp.appending(path: "repo-a/.git"), withIntermediateDirectories: true)
        // Level 2: group/repo-b/.git
        try fm.createDirectory(
            at: tmp.appending(path: "group/repo-b/.git"), withIntermediateDirectories: true)
        // Level 3: org/team/repo-c/.git
        try fm.createDirectory(
            at: tmp.appending(path: "org/team/repo-c/.git"), withIntermediateDirectories: true)
        // Level 4 (too deep): org/team/sub/repo-d/.git
        try fm.createDirectory(
            at: tmp.appending(path: "org/team/sub/repo-d/.git"), withIntermediateDirectories: true)
        // Not a repo: no-git/
        try fm.createDirectory(at: tmp.appending(path: "no-git"), withIntermediateDirectories: true)

        // Act
        let scanner = RepoScanner()
        let repos = scanner.scanForGitRepos(in: tmp, maxDepth: 3)

        // Assert
        #expect(repos.count == 3)
        let names = Set(repos.map(\.lastPathComponent))
        #expect(names.contains("repo-a"))
        #expect(names.contains("repo-b"))
        #expect(names.contains("repo-c"))
        #expect(!names.contains("repo-d"))

        // Cleanup
        try? fm.removeItem(at: tmp)
    }

    @Test("does not descend into .git directories")
    func skipsGitInternals() throws {
        // Arrange
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "scanner-skip-\(UUID().uuidString)")
        let fm = FileManager.default

        // repo/.git/modules/sub (should not be detected as separate repo)
        try fm.createDirectory(
            at: tmp.appending(path: "repo/.git/modules/sub/.git"),
            withIntermediateDirectories: true)

        // Act
        let scanner = RepoScanner()
        let repos = scanner.scanForGitRepos(in: tmp, maxDepth: 3)

        // Assert
        #expect(repos.count == 1)
        #expect(repos[0].lastPathComponent == "repo")

        // Cleanup
        try? fm.removeItem(at: tmp)
    }

    @Test("returns sorted results by name")
    func sortsByName() throws {
        // Arrange
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "scanner-sort-\(UUID().uuidString)")
        let fm = FileManager.default

        try fm.createDirectory(
            at: tmp.appending(path: "zebra/.git"), withIntermediateDirectories: true)
        try fm.createDirectory(
            at: tmp.appending(path: "alpha/.git"), withIntermediateDirectories: true)
        try fm.createDirectory(
            at: tmp.appending(path: "middle/.git"), withIntermediateDirectories: true)

        // Act
        let repos = RepoScanner().scanForGitRepos(in: tmp, maxDepth: 3)

        // Assert
        #expect(repos.map(\.lastPathComponent) == ["alpha", "middle", "zebra"])

        // Cleanup
        try? fm.removeItem(at: tmp)
    }

    @Test("empty directory returns empty")
    func emptyDirectory() throws {
        // Arrange
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "scanner-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        // Act
        let repos = RepoScanner().scanForGitRepos(in: tmp, maxDepth: 3)

        // Assert
        #expect(repos.isEmpty)

        // Cleanup
        try? FileManager.default.removeItem(at: tmp)
    }
}
