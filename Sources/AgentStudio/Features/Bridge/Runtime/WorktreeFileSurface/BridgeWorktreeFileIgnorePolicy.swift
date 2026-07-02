import AgentStudioGit
import Foundation

struct BridgeWorktreeFileIgnorePolicy: Sendable {
    static let empty = Self(
        filesystemPathFilter: FilesystemPathFilter.empty,
        publishableFilePaths: nil
    )

    private let filesystemPathFilter: FilesystemPathFilter

    /// Git-truth publishable manifest computed at open: tracked index paths
    /// (excluding submodules) plus untracked-not-ignored status entries,
    /// minus worktree deletions and rename sources. Neither input ever
    /// materializes the ignored universe — `trackedPaths` reads the index
    /// and `status(includeIgnored: false)` prunes ignored directories at
    /// their boundary. `nil` means the root is not a git worktree and
    /// enumeration falls back to the filesystem walk.
    let publishableFilePaths: Set<String>?

    init(filesystemPathFilter: FilesystemPathFilter, publishableFilePaths: Set<String>?) {
        self.filesystemPathFilter = filesystemPathFilter
        self.publishableFilePaths = publishableFilePaths
    }

    static func load(rootURL: URL) async -> Self {
        async let filesystemPathFilter = FilesystemPathFilter.loadOffExecutor(forRootPath: rootURL)
        let publishableFilePaths = await publishableFilePaths(rootURL: rootURL)
        return await Self(
            filesystemPathFilter: filesystemPathFilter,
            publishableFilePaths: publishableFilePaths
        )
    }

    func isIgnored(relativePath: String) -> Bool {
        let normalizedPath = Self.normalized(relativePath)
        guard !normalizedPath.isEmpty, normalizedPath != "." else {
            return false
        }
        // A path in the publishable manifest is git-truth published; only
        // paths outside it (new files, directories) fall back to the root
        // gitignore rules.
        if let publishableFilePaths, publishableFilePaths.contains(normalizedPath) {
            return false
        }
        return filesystemPathFilter.isIgnored(relativePath: normalizedPath)
    }

    private static func publishableFilePaths(rootURL: URL) async -> Set<String>? {
        let client = LibGit2AgentStudioGitLocalClient()
        do {
            let trackedSnapshot = try await client.trackedPaths(
                for: rootURL,
                options: GitTrackedPathsOptions()
            )
            let statusSnapshot = try await client.status(
                for: rootURL,
                options: GitStatusOptions(includeIgnored: false, includeUntracked: true)
            )
            // Submodule gitlinks stay in the manifest: they surface as
            // non-expanded directory rows (the enumerator never descends
            // into paths that have no published files beneath them).
            var publishablePaths = Set(
                trackedSnapshot.entries
                    .map { normalized($0.path) }
                    .filter { !$0.isEmpty }
            )
            for entry in statusSnapshot.entries {
                let path = normalized(entry.path)
                if let previousPath = entry.previousPath {
                    publishablePaths.remove(normalized(previousPath))
                }
                guard !path.isEmpty, !path.hasSuffix("/") else {
                    continue
                }
                let deletedFromWorktree =
                    entry.worktreeState == .deleted
                    || (entry.indexState == .deleted && entry.worktreeState == nil)
                if deletedFromWorktree {
                    publishablePaths.remove(path)
                } else {
                    publishablePaths.insert(path)
                }
            }
            return publishablePaths
        } catch {
            return nil
        }
    }

    private static func normalized(_ relativePath: String) -> String {
        var normalizedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalizedPath.hasPrefix("./") {
            normalizedPath.removeFirst(2)
        }
        while normalizedPath.hasPrefix("/") {
            normalizedPath.removeFirst()
        }
        return normalizedPath
    }
}
