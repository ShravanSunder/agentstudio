import Foundation

package enum WorktreeDestinationNaming {
    /// Folder-safe form of a branch name: `feat/worktree-commands` becomes
    /// `feat-worktree-commands`. Returns `nil` when the branch has no folder-safe characters.
    package static func folderSlug(for branchName: WorktreeBranchName) -> String? {
        var slug = ""
        for character in branchName.rawValue {
            let isFolderSafe =
                character.isASCII && (character.isLetter || character.isNumber || "._-".contains(character))
            let mapped: Character = isFolderSafe ? character : "-"
            guard !(mapped == "-" && slug.last == "-") else { continue }
            slug.append(mapped)
        }
        slug = trimmedSlug(String(slug.prefix(WorktreeCreationPolicy.maximumDestinationSlugLength)))
        return slug.isEmpty ? nil : slug
    }

    /// Places the new worktree beside the supplied repository checkout, using the
    /// command bar's branch-derived sibling-name rule.
    package static func siblingPath(repositoryPath: URL, branchName: WorktreeBranchName) -> URL? {
        guard let slug = folderSlug(for: branchName) else { return nil }
        let repositoryFolder = repositoryPath.standardizedFileURL
        return repositoryFolder.deletingLastPathComponent().appending(
            path: repositoryFolder.lastPathComponent + WorktreeCreationPolicy.destinationSlugSeparator + slug,
            directoryHint: .isDirectory
        ).standardizedFileURL
    }

    private static func trimmedSlug(_ slug: String) -> String {
        slug.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
    }
}
