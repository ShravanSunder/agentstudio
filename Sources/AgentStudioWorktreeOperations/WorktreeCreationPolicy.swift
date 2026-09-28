package enum WorktreeCreationPolicy {
    /// Longest branch name accepted before the Git ref and destination slug are derived.
    package static let maximumBranchNameLength: Int = 200
    /// Longest branch-derived folder suffix; keeps the sibling path well under PATH_MAX.
    package static let maximumDestinationSlugLength: Int = 80
    /// Joins the source repository folder and the branch slug: `<repo-folder>.<branch-slug>`.
    package static let destinationSlugSeparator: String = "."
}
