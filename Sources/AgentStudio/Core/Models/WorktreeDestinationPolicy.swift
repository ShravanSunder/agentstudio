import AgentStudioInfrastructure
import Foundation

/// Where a new worktree lands and which watched folder will publish it.
package struct WorktreeCreationDestination: Equatable, Sendable {
    package let path: URL
    package let watchedPath: WatchedPath
}

package enum WorktreeDestinationRejection: Error, Equatable, Sendable {
    /// The branch name has no characters a folder name can carry.
    case emptyFolderSlug
    /// No watched folder would discover the destination, so it would never reach the sidebar.
    case undiscoverableDestination(URL)
    /// The destination sits deeper below its watched folder than the scanner descends.
    case beyondScannerDepth(URL, maximumDepth: Int)
    case destinationExists(URL)
}

/// Places a new worktree as a sibling of its repository's main checkout,
/// `<parent>/<repo-folder>.<branch-slug>`, and admits it only where a watched-folder
/// scan will discover it. The sibling sits at the main checkout's depth, which that
/// scan already reached.
package enum WorktreeDestinationPolicy {
    package static func resolve(
        repositoryPath: URL,
        branchName: WorktreeBranchName,
        watchedPaths: [WatchedPath],
        pathExists: (URL) -> Bool
    ) -> Result<WorktreeCreationDestination, WorktreeDestinationRejection> {
        guard let slug = folderSlug(for: branchName) else { return .failure(.emptyFolderSlug) }
        let repositoryFolder = repositoryPath.standardizedFileURL
        let destination = repositoryFolder.deletingLastPathComponent().appending(
            path: repositoryFolder.lastPathComponent + AppPolicies.WorktreeCreation.destinationSlugSeparator + slug,
            directoryHint: .isDirectory
        ).standardizedFileURL
        guard let discovery = discoveringWatchedPath(for: destination, in: watchedPaths) else {
            return .failure(.undiscoverableDestination(destination))
        }
        guard discovery.depthBelowRoot <= RepoScanner.defaultMaxDepth else {
            return .failure(.beyondScannerDepth(destination, maximumDepth: RepoScanner.defaultMaxDepth))
        }
        let watchedPath = discovery.watchedPath
        guard !pathExists(destination) else { return .failure(.destinationExists(destination)) }
        return .success(WorktreeCreationDestination(path: destination, watchedPath: watchedPath))
    }

    /// Folder-safe form of a branch name: `feat/worktree-commands` becomes
    /// `feat-worktree-commands`.
    package static func folderSlug(for branchName: WorktreeBranchName) -> String? {
        var slug = ""
        for character in branchName.rawValue {
            let isFolderSafe =
                character.isASCII && (character.isLetter || character.isNumber || "._-".contains(character))
            let mapped: Character = isFolderSafe ? character : "-"
            guard !(mapped == "-" && slug.last == "-") else { continue }
            slug.append(mapped)
        }
        slug = trimmedSlug(String(slug.prefix(AppPolicies.WorktreeCreation.maximumDestinationSlugLength)))
        return slug.isEmpty ? nil : slug
    }

    private static func trimmedSlug(_ slug: String) -> String {
        slug.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
    }

    /// The deepest watched folder that strictly contains the destination through
    /// non-hidden folders (scans skip hidden directories), with the destination's depth
    /// below it; the deepest root gives the shallowest, most discoverable depth.
    private static func discoveringWatchedPath(
        for destination: URL,
        in watchedPaths: [WatchedPath]
    ) -> (watchedPath: WatchedPath, depthBelowRoot: Int)? {
        let destinationComponents = canonicalComponents(of: destination)
        return
            watchedPaths
            .compactMap { watchedPath -> (watchedPath: WatchedPath, depthBelowRoot: Int)? in
                let rootComponents = canonicalComponents(of: watchedPath.path)
                guard destinationComponents.count > rootComponents.count,
                    destinationComponents.starts(with: rootComponents),
                    !destinationComponents.dropFirst(rootComponents.count).contains(where: { $0.hasPrefix(".") })
                else { return nil }
                return (watchedPath, destinationComponents.count - rootComponents.count)
            }
            .min { $0.depthBelowRoot < $1.depthBelowRoot }
    }

    private static func canonicalComponents(of url: URL) -> [String] {
        let canonicalPath = FilesystemRootOwnership.canonicalizeKernelPath(url.standardizedFileURL.path)
        return URL(fileURLWithPath: canonicalPath).pathComponents
    }
}
