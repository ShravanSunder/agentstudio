func goodWorktreeComparator() {
    _ = AtomFamily<UUID, WorktreeEnrichment>(
        isContentEqual: { lhs, rhs in lhs.id == rhs.id && lhs.status == rhs.status }
    )
}
