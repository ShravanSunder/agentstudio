extension OrderedFactJournal {
    func captureReplayState(state: State) -> [SequencedFact<Fact>] {
        state.history.records.map(\.sequencedFact)
    }
}
