extension OrderedFactJournal {
    func exposeJournalStorage(
        state: inout OrderedFactJournal<Fact, Snapshot>.State,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        lock.withLock { _ in
            _ = state
            _ = token
        }
    }
}
