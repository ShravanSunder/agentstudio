struct InitializerAndSubscriptConsumers {
    init(
        journal: OrderedFactJournal<Int, String>,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        _ = journal
        _ = token
    }

    subscript(
        journal journal: OrderedFactJournal<Int, String>,
        token token: borrowing AdmissionProtectedRegionToken
    ) -> Int {
        _ = journal
        _ = token
        return 0
    }
}
