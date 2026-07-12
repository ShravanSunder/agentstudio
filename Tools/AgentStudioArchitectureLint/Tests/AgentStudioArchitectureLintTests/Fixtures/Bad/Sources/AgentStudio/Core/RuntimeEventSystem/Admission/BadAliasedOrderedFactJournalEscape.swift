typealias RenamedJournal<Fact, Snapshot> = OrderedFactJournal<Fact, Snapshot>

extension RenamedJournal {
    typealias RenamedStorage = State

    func exposeRenamedStorage(state: inout RenamedStorage) {
        _ = state
    }
}
