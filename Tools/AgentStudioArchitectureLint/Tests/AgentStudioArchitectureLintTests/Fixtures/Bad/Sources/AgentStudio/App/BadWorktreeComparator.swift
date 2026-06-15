func badWorktreeComparator() {
    _ = AtomEntityMap<UUID, WorktreeEnrichment>(
        isContentEqual: { lhs, rhs in lhs == rhs }
    )
}
