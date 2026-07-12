func retainLocalCanonicalShadow() {
    typealias OrderedFactJournal<Fact, Snapshot> = String
    let retained: (OrderedFactJournal<Int, String>, AdmissionProtectedRegionToken)? = nil
    _ = retained
}

func consumeTopLevelCanonical(
    journal: OrderedFactJournal<Int, String>,
    token: borrowing AdmissionProtectedRegionToken
) {
    _ = journal
    _ = token
}

func consumeLocalJournalAlias() {
    typealias Handle<Fact, Snapshot> = OrderedFactJournal<Fact, Snapshot>
    let escaped: (Handle<Int, String>, AdmissionProtectedRegionToken)? = nil
    _ = escaped
}

func retainSeparateLocalAlias() {
    typealias Handle<Fact, Snapshot> = String
    let retained: (Handle<Int, String>, AdmissionProtectedRegionToken)? = nil
    _ = retained
}
