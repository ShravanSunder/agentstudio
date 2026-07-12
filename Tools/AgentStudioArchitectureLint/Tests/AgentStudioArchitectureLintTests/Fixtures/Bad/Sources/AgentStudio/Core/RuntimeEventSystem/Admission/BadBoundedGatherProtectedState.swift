extension BoundedGatherMailbox {
    func ageMeasurement(state: State) -> Duration? {
        var oldestRetainedAt: Duration?

        for keyState in state.keyStates {
            oldestRetainedAt = minimumAdmissionTimestamp(
                oldestRetainedAt,
                keyState.oldestPendingAt
            )
        }
        return oldestRetainedAt
    }
}
