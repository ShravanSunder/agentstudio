func badDerivedValue() {
    _ = DerivedValue<Int>(
        inputRevisions: { [0] },
        isContentEqual: ==
    ) {
        hiddenRepoCacheRead()
    }
}

func hiddenRepoCacheRead() -> Int {
    AtomReader.repoCache.repoEnrichmentByRepoId.count
}
