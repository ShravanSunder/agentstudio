func rejectCanonicalJournalAndToken(
    journal: OrderedFactJournal<Int, String>,
    token: borrowing AdmissionProtectedRegionToken
) {
    _ = journal
    _ = token
}

extension OrderedFactJournal {
    func rejectCanonicalState(_ state: State) {
        _ = state
    }
}

extension OrderedFactJournal {
    func rejectCanonicalRawLock(_ lock: OSAllocatedUnfairLock<State>) {
        _ = lock
    }
}
