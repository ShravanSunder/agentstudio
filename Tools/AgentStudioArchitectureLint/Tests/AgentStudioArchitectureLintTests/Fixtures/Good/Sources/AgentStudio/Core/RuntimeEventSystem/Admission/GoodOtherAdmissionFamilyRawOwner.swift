final class LatestValueMailbox<Value> {
    private struct State {
        var value: Value?
    }

    private typealias RenamedLatestState = State
    private let lock: OSAllocatedUnfairLock<RenamedLatestState>

    private func mutateLatestState(
        state: inout RenamedLatestState,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        lock.withLock { _ in
            _ = state
            _ = token
        }
    }
}
