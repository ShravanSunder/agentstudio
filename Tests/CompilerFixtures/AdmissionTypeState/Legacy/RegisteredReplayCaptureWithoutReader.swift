func constructRegisteredReplayCaptureWithoutReader()
    -> OrderedFactReplayCapture<Int, Int>
{
    OrderedFactReplayCapture(
        readerIdentity: nil,
        content: .history(
            OrderedFactReplayHistoryCapture(
                bounds: OrderedFactReplayBounds(firstNode: nil, stopNode: nil),
                afterSequence: 0,
                latestSequence: 0,
                historyUnavailableThrough: 0,
                snapshot: nil,
                recovery: .exactHistory
            )
        )
    )
}
