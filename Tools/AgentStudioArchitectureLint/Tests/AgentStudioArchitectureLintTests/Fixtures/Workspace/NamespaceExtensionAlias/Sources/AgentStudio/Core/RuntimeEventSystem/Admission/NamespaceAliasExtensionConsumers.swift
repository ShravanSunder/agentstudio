extension OuterAlias.Inner {
    func consumeJournalHandle(
        journal: Handle<Int, String>,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        _ = journal
        _ = token
    }
}

extension UnrelatedOuterAlias.Inner {
    func retainUnrelatedHandle(
        journal: Handle<Int, String>,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        _ = journal
        _ = token
    }
}
