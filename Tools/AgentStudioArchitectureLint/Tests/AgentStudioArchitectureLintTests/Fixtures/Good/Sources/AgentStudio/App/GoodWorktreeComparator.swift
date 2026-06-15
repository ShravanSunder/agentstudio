func goodWorktreeComparator() {
    _ = AtomEntityMap<UUID, WorktreeEnrichment>(
        isContentEqual: { lhs, rhs in lhs.id == rhs.id && lhs.status == rhs.status }
    )
}
