struct BadNestedJournalTokenConsumers {
    let escapedAuthority: (OrderedFactJournal<Int, String>, AdmissionProtectedRegionToken)?

    func consume(
        journal: OrderedFactJournal<Int, String>,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        _ = journal
        _ = token
    }

    struct ChildConsumer {
        let escapedAuthority: (OrderedFactJournal<Int, String>, AdmissionProtectedRegionToken)?

        func consume(
            journal: OrderedFactJournal<Int, String>,
            token: borrowing AdmissionProtectedRegionToken
        ) {
            _ = journal
            _ = token
        }
    }
}
