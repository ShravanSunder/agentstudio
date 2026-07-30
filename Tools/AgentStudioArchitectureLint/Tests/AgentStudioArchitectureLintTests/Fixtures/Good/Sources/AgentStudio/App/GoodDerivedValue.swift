func goodDerivedValueInputName() {
    struct LocalProbe {
        let atom = 42
    }

    let probe = LocalProbe()
    _ = probe.atom
}
