import Foundation

/// Scans a directory tree for git repositories up to a configurable depth.
struct RepoScanner {
    enum GitEntryKind: Sendable, Equatable {
        case cloneRoot
        case linkedWorktree(parentClonePath: URL)
    }

    struct RepoScanGroup: Sendable, Equatable {
        let clonePath: URL
        let linkedWorktreePaths: [URL]
    }

    /// Default scan depth for parent folder discovery.
    /// Depth 4 supports layouts like ~/projects/org/suborg/repo/.git.
    /// Scanning stops at the first .git boundary (no deeper).
    static let defaultMaxDepth = 4

    /// Scans `rootURL` for directories containing a `.git` subdirectory.
    /// Stops descending into a directory once a `.git` is found (no nested repos).
    /// Skips hidden directories and symlinks.
    func scanForGitRepos(in rootURL: URL, maxDepth: Int = Self.defaultMaxDepth) -> [URL] {
        var repos: [URL] = []
        scanDirectory(rootURL, currentDepth: 0, maxDepth: maxDepth, results: &repos)
        return repos.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent)
                == .orderedAscending
        }
    }

    func scanForGitReposGrouped(in rootURL: URL, maxDepth: Int = Self.defaultMaxDepth) -> [RepoScanGroup] {
        var classifiedPaths: [(path: URL, kind: GitEntryKind)] = []
        scanDirectory(
            rootURL,
            currentDepth: 0,
            maxDepth: maxDepth,
            classifiedResults: &classifiedPaths
        )
        return Self.groupClassifiedPaths(classifiedPaths)
    }

    private func scanDirectory(
        _ url: URL, currentDepth: Int, maxDepth: Int, results: inout [URL]
    ) {
        guard currentDepth <= maxDepth else { return }

        let fm = FileManager.default
        // .git is always a hard boundary: classify this path, then stop.
        if Self.classifyGitEntry(at: url) != nil {
            if Self.isValidGitWorkingTree(url) {
                results.append(url)
            }
            return
        }

        // Otherwise, scan subdirectories
        guard
            let contents = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        else { return }

        for item in contents {
            guard
                let values = try? item.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                values.isDirectory == true,
                values.isSymbolicLink != true
            else { continue }

            scanDirectory(
                item, currentDepth: currentDepth + 1, maxDepth: maxDepth, results: &results)
        }
    }

    private func scanDirectory(
        _ url: URL,
        currentDepth: Int,
        maxDepth: Int,
        classifiedResults: inout [(path: URL, kind: GitEntryKind)]
    ) {
        guard currentDepth <= maxDepth else { return }

        let fileManager = FileManager.default
        if let gitEntryKind = Self.classifyGitEntry(at: url) {
            if Self.isValidGitWorkingTree(url) {
                classifiedResults.append((path: url, kind: gitEntryKind))
            }
            return
        }

        guard
            let contents = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        else { return }

        for item in contents {
            guard
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                values.isDirectory == true,
                values.isSymbolicLink != true
            else { continue }

            scanDirectory(
                item,
                currentDepth: currentDepth + 1,
                maxDepth: maxDepth,
                classifiedResults: &classifiedResults
            )
        }
    }

    static func classifyGitEntry(at url: URL) -> GitEntryKind? {
        let gitMarkerPath = url.appending(path: ".git")
        guard FileManager.default.fileExists(atPath: gitMarkerPath.path) else { return nil }

        guard let values = try? gitMarkerPath.resourceValues(forKeys: [.isDirectoryKey]),
            let isDirectory = values.isDirectory
        else {
            // .git exists but can't stat — treat as clone root boundary so scanner stops descending
            return .cloneRoot
        }

        if isDirectory {
            return .cloneRoot
        }

        guard
            let gitFileContents = try? String(contentsOf: gitMarkerPath, encoding: .utf8),
            let parentClonePath = parseParentClonePath(
                fromGitFileContent: gitFileContents,
                relativeTo: url
            )
        else {
            // .git file exists but unreadable or unparseable — treat as clone root boundary
            return .cloneRoot
        }

        return .linkedWorktree(parentClonePath: parentClonePath)
    }

    static func parseParentClonePath(fromGitFileContent gitFileContent: String) -> URL? {
        parseParentClonePath(fromGitFileContent: gitFileContent, relativeTo: nil)
    }

    static func groupClassifiedPaths(_ classifiedPaths: [(URL, GitEntryKind)]) -> [RepoScanGroup] {
        var groupedByClonePath: [URL: [URL]] = [:]

        for (path, kind) in classifiedPaths {
            switch kind {
            case .cloneRoot:
                let clonePath = path.standardizedFileURL
                if groupedByClonePath[clonePath] == nil {
                    groupedByClonePath[clonePath] = []
                }
            case .linkedWorktree(let parentClonePath):
                groupedByClonePath[parentClonePath.standardizedFileURL, default: []]
                    .append(path)
            }
        }

        return
            groupedByClonePath
            .map { clonePath, linkedWorktreePaths in
                RepoScanGroup(
                    clonePath: clonePath,
                    linkedWorktreePaths: linkedWorktreePaths.sorted {
                        $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent)
                            == .orderedAscending
                    }
                )
            }
            .sorted {
                $0.clonePath.lastPathComponent.localizedCaseInsensitiveCompare($1.clonePath.lastPathComponent)
                    == .orderedAscending
            }
    }

    private static func isValidGitWorkingTree(_ url: URL) -> Bool {
        guard let isWorkTree = runGit(url: url, args: ["rev-parse", "--is-inside-work-tree"]),
            isWorkTree == "true"
        else {
            return false
        }

        // Submodule working trees are nested implementation details of a parent repo.
        // They should not appear as standalone sidebar repos in folder scans.
        if let superprojectRoot = runGit(url: url, args: ["rev-parse", "--show-superproject-working-tree"]),
            !superprojectRoot.isEmpty
        {
            return false
        }

        return true
    }

    private static func runGit(url: URL, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", url.path] + args

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(
                data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private static func parseParentClonePath(
        fromGitFileContent gitFileContent: String,
        relativeTo worktreeURL: URL?
    ) -> URL? {
        let trimmedContent = gitFileContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedContent.hasPrefix("gitdir:") else { return nil }

        let gitDirPathString =
            trimmedContent
            .dropFirst("gitdir:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let gitDirURL: URL
        if gitDirPathString.hasPrefix("/") {
            gitDirURL = URL(fileURLWithPath: gitDirPathString)
        } else if let worktreeURL {
            gitDirURL =
                worktreeURL
                .appending(path: gitDirPathString)
                .standardizedFileURL
        } else {
            return nil
        }

        let gitDirPath = gitDirURL.standardizedFileURL.path
        guard let worktreeRange = gitDirPath.range(of: "/.git/worktrees/") else { return nil }
        return URL(fileURLWithPath: String(gitDirPath[..<worktreeRange.lowerBound])).standardizedFileURL
    }
}
