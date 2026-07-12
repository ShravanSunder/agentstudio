func constructCurrentRegisteredReplayWithRegisteredResult()
    -> OrderedFactReplayCompletion<Int, Int>
{
    .registered(.facts([], nextSequence: 0), wake: .scheduleDrain)
}
