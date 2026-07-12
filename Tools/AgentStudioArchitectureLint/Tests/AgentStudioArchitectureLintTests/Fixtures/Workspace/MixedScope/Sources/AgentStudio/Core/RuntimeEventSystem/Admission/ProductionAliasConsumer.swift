func retainUnresolvedNestedTestAlias(
    journal: NestedTestJournalAlias<Int, String>,
    token: borrowing AdmissionProtectedRegionToken
) {
    _ = journal
    _ = token
}
