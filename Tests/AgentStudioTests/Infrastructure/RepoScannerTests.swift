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

        // Level 1: repo-a
        try initializeGitRepository(at: tmp.appending(path: "repo-a"))
        // Level 2: group/repo-b
        try initializeGitRepository(at: tmp.appending(path: "group/repo-b"))
        // Level 3: org/team/repo-c
        try initializeGitRepository(at: tmp.appending(path: "org/team/repo-c"))
        // Level 4 (too deep): org/team/sub/repo-d
        try initializeGitRepository(at: tmp.appending(path: "org/team/sub/repo-d"))
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
        try? FileManager.default.removeItem(at: tmp)
    }

    @Test("does not descend into .git directories")
    func skipsGitInternals() throws {
        // Arrange
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "scanner-skip-\(UUID().uuidString)")
        let repoPath = tmp.appending(path: "repo")
        try initializeGitRepository(at: repoPath)
        try FileManager.default.createDirectory(
            at: repoPath.appending(path: ".git/modules/sub/.git"),
            withIntermediateDirectories: true
        )

        // Act
        let scanner = RepoScanner()
        let repos = scanner.scanForGitRepos(in: tmp, maxDepth: 3)

        // Assert
        #expect(repos.count == 1)
        #expect(repos.first?.lastPathComponent == "repo")

        // Cleanup
        try? FileManager.default.removeItem(at: tmp)
    }

    @Test("returns sorted results by name")
    func sortsByName() throws {
        // Arrange
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "scanner-sort-\(UUID().uuidString)")

        try initializeGitRepository(at: tmp.appending(path: "zebra"))
        try initializeGitRepository(at: tmp.appending(path: "alpha"))
        try initializeGitRepository(at: tmp.appending(path: "middle"))

        // Act
        let repos = RepoScanner().scanForGitRepos(in: tmp, maxDepth: 3)

        // Assert
        #expect(repos.map(\.lastPathComponent) == ["alpha", "middle", "zebra"])

        // Cleanup
        try? FileManager.default.removeItem(at: tmp)
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

    @Test("scan stops at .git boundary and does not descend further")
    func scanStopsAtGitBoundary() throws {
        // Arrange
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "scanner-worktrees-\(UUID().uuidString)")
        let fm = FileManager.default

        // Parent has a .git marker but is not a valid working tree.
        // Scanner must stop here and never descend into children.
        try fm.createDirectory(
            at: tmp.appending(path: "-worktrees/.git"),
            withIntermediateDirectories: true
        )
        // Child repos under a .git boundary must not be discovered.
        try initializeGitRepository(at: tmp.appending(path: "-worktrees/agent-studio/feature-a"))
        try initializeGitRepository(at: tmp.appending(path: "-worktrees/askluna-finance/transaction-table-3"))
        // Sibling repo outside the .git boundary should still be discovered.
        try initializeGitRepository(at: tmp.appending(path: "standalone-repo"))

        // Act
        let repos = RepoScanner().scanForGitRepos(in: tmp, maxDepth: 4)

        // Assert
        let discoveredPaths = Set(repos.map(canonicalPath(_:)))
        #expect(!discoveredPaths.contains(canonicalPath(tmp.appending(path: "-worktrees"))))
        #expect(!discoveredPaths.contains(canonicalPath(tmp.appending(path: "-worktrees/agent-studio/feature-a"))))
        #expect(
            !discoveredPaths.contains(
                canonicalPath(tmp.appending(path: "-worktrees/askluna-finance/transaction-table-3"))))
        #expect(discoveredPaths.contains(canonicalPath(tmp.appending(path: "standalone-repo"))))

        // Cleanup
        try? fm.removeItem(at: tmp)
    }

    @Test("ignores stale git marker paths that are not valid worktrees")
    func ignoresInvalidGitMarkers() throws {
        // Arrange
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "scanner-invalid-marker-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)

        let validRepoPath = tmp.appending(path: "valid-repo")
        let invalidWorktreePath = tmp.appending(path: "agent-studio.window-system")
        try fm.createDirectory(at: invalidWorktreePath, withIntermediateDirectories: true)
        try "gitdir: /tmp/non-existent/.git/worktrees/agent-studio.window-system\n".write(
            to: invalidWorktreePath.appending(path: ".git"),
            atomically: true,
            encoding: .utf8
        )

        // Make valid-repo pass real git validation.
        try initializeGitRepository(at: validRepoPath)

        // Act
        let repos = RepoScanner().scanForGitRepos(in: tmp, maxDepth: 2)
        let discoveredPaths = Set(repos.map(canonicalPath(_:)))

        // Assert
        #expect(discoveredPaths.contains(canonicalPath(validRepoPath)))
        #expect(!discoveredPaths.contains(canonicalPath(invalidWorktreePath)))

        // Cleanup
        try? fm.removeItem(at: tmp)
    }

    @Test("real project-dev invalid worktree path is filtered out")
    func realProjectDevInvalidWorktreePathIsFilteredOut() {
        let root = URL(fileURLWithPath: "/Users/shravansunder/Documents/dev/project-dev")
        let invalidPath = root.appending(path: "agent-studio.window-system")
        guard FileManager.default.fileExists(atPath: invalidPath.path) else {
            return
        }

        let repos = RepoScanner().scanForGitRepos(in: root, maxDepth: 3)
        let discoveredPaths = Set(repos.map(canonicalPath(_:)))
        #expect(!discoveredPaths.contains(canonicalPath(invalidPath)))
    }

    @Test("submodule working trees are filtered out")
    func submoduleWorkingTreesAreFilteredOut() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "scanner-submodule-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let submoduleSourcePath = tmp.appending(path: "ghostty-source")
        try initializeGitRepository(at: submoduleSourcePath)
        try "ghostty\n".write(
            to: submoduleSourcePath.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(
            at: submoduleSourcePath,
            args: ["add", "README.md"]
        )
        try runGit(
            at: submoduleSourcePath,
            args: ["commit", "-m", "Initial commit"]
        )

        let superRepoPath = tmp.appending(path: "agent-studio.window-system")
        try initializeGitRepository(at: superRepoPath)
        try runGit(
            at: superRepoPath,
            args: [
                "-c", "protocol.file.allow=always",
                "submodule", "add",
                submoduleSourcePath.path,
                "vendor/ghostty",
            ]
        )

        let repos = RepoScanner().scanForGitRepos(in: tmp, maxDepth: 4)
        let discoveredPaths = Set(repos.map(canonicalPath(_:)))
        #expect(discoveredPaths.contains(canonicalPath(superRepoPath)))
        #expect(!discoveredPaths.contains(canonicalPath(superRepoPath.appending(path: "vendor/ghostty"))))
    }

    @Test("real project-dev ghostty submodule path is filtered out")
    func realProjectDevGhosttySubmodulePathIsFilteredOut() {
        let root = URL(fileURLWithPath: "/Users/shravansunder/Documents/dev/project-dev")
        let ghosttyPath = root.appending(path: "agent-studio.window-system/vendor/ghostty")
        guard FileManager.default.fileExists(atPath: ghosttyPath.path) else {
            return
        }

        let repos = RepoScanner().scanForGitRepos(in: root, maxDepth: 4)
        let discoveredPaths = Set(repos.map(canonicalPath(_:)))
        #expect(!discoveredPaths.contains(canonicalPath(ghosttyPath)))
    }

    private func initializeGitRepository(at path: URL) throws {
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        try runGit(at: path, args: ["init"])
        try runGit(at: path, args: ["config", "user.email", "scanner-tests@example.com"])
        try runGit(at: path, args: ["config", "user.name", "Scanner Tests"])
        try runGit(at: path, args: ["config", "commit.gpgsign", "false"])
    }

    private func runGit(at path: URL, args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", path.path] + args
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            Issue.record("git command failed: \(args.joined(separator: " ")) stderr=\(stderr)")
            throw NSError(domain: "RepoScannerTests", code: Int(process.terminationStatus))
        }
    }

    private func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
