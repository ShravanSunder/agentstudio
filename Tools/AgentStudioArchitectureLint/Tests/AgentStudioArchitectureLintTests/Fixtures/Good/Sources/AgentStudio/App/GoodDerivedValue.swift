func goodDerivedValue(revision: AtomRevision) {
    struct LocalProbe {
        let atom = 42
    }

    let probe = LocalProbe()
    _ = DerivedValue<Int>(
        inputRevisions: { [revision.value] },
        isContentEqual: ==,
        compute: {
            probe.atom
        }
    )
}
