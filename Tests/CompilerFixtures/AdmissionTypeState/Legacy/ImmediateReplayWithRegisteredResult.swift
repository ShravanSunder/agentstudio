func constructLegacyImmediateReplayWithRegisteredResult()
    -> OrderedFactReplayCompletion<Int, Int>
{
    .init(result: .facts([], nextSequence: 0), wake: .noWake)
}
