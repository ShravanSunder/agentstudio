extension OrderedFactJournal {
    func retainOtherState(state: Other.State) {
        _ = state
    }
}

extension OrderedFactJournal {
    func exposeBareState(state: State) {
        _ = state
    }
}

typealias JournalStateAlias = OrderedFactJournal<Int, String>.State

extension OrderedFactJournal {
    func exposeAliasedState(state: JournalStateAlias) {
        _ = state
    }
}

extension OrderedFactJournal {
    func retainLocalOtherState() {
        typealias State = Other.State
        let value: State? = nil
        _ = value
    }
}

extension OrderedFactJournal {
    func exposeLocalRawStateAlias() {
        typealias LocalState = State
        let value: LocalState? = nil
        _ = value
    }
}
