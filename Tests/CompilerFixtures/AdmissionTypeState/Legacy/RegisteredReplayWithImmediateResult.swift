func constructLegacyRegisteredReplayWithImmediateResult()
    -> OrderedFactReplayCompletion<Int, Int>
{
    .init(result: .invalidated, wake: .scheduleDrain)
}
