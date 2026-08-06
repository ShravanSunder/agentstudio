func badWorktreeComparator() {
    _ = AtomFamily<UUID, WorktreeEnrichment>(
        isContentEqual: { lhs, rhs in lhs == rhs }
    )
}
