typealias NestedTestJournalAlias<Fact, Snapshot> = OrderedFactJournal<Fact, Snapshot>

func consumeNestedTestAuthority(
    journal: OrderedFactJournal<Int, String>,
    token: borrowing AdmissionProtectedRegionToken
) {
    _ = journal
    _ = token
}
