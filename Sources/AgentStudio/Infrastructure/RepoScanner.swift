import Foundation

/// Scans a directory tree for git repositories up to a configurable depth.
struct RepoScanner {

    /// Scans `rootURL` for directories containing a `.git` subdirectory.
    /// Stops descending into a directory once a `.git` is found (no nested repos).
    /// Skips hidden directories and symlinks.
    func scanForGitRepos(in rootURL: URL, maxDepth: Int = 3) -> [URL] {
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

        // If this directory has .git, it's a repo — don't descend further
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: gitDir.path, isDirectory: &isDirectory) {
            results.append(url)
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
}
