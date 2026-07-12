func constructCurrentImmediateReplayWithRegisteredResult()
    -> OrderedFactReplayCompletion<Int, Int>
{
    let registeredResult = OrderedFactRegisteredReplayResult<Int, Int>.facts(
        [],
        nextSequence: 0
    )
    return .immediate(registeredResult)
}
