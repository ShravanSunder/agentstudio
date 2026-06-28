func badDerivedValue() {
    _ = DerivedValue<Int>(
        inputRevisions: { [0] },
        isContentEqual: ==,
        compute: {
            hiddenRepoCacheRead()
        }
    )
}

func hiddenRepoCacheRead() -> Int {
    AtomReader.repoCache.repoEnrichmentByRepoId.count
}
