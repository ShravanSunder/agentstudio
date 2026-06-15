func goodDerivedValue(revision: AtomRevision) {
    _ = DerivedValue<Int>(
        inputRevisions: { [revision.value] },
        isContentEqual: ==
    ) {
        42
    }
}
