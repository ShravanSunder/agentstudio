import Foundation

/// Scans a directory tree for git repositories up to a configurable depth.
struct RepoScanner {

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

    private func scanDirectory(
        _ url: URL, currentDepth: Int, maxDepth: Int, results: inout [URL]
    ) {
        guard currentDepth <= maxDepth else { return }

        let fm = FileManager.default
        let gitDir = url.appending(path: ".git")

        // .git is always a hard boundary: classify this path, then stop.
        if fm.fileExists(atPath: gitDir.path) {
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
}
