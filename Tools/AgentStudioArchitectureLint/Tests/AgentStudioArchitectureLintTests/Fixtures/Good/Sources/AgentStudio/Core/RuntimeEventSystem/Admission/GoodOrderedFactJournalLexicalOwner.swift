final class OrderedFactJournal<Fact, Snapshot> {
    private struct State {
        var factCount = 0
    }

    private let lock: OSAllocatedUnfairLock<State>
}

extension OrderedFactJournal {
    func captureReplayState(state: State) -> ReplayCapture {
        ReplayCapture(
            startNode: state.history.firstPendingNode,
            stopNode: state.history.tailNode
        )
    }

    func typedDiagnostics() -> Int {
        0
    }
}
