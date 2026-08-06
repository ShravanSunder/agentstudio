func goodDerivedAtom(revision: AtomRevision) {
    struct LocalProbe {
        let atom = 42
    }

    let probe = LocalProbe()
    _ = DerivedAtom<Int>(
        inputRevisions: { [revision.value] },
        isContentEqual: ==,
        compute: { probe.atom }
    )
}
