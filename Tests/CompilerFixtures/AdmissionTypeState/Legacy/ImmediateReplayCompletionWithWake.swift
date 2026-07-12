func constructImmediateReplayCompletionWithWake()
    -> OrderedFactReplayCompletion<Int, Int>
{
    OrderedFactReplayCompletion(
        result: .invalidated,
        wake: .scheduleDrain
    )
}
