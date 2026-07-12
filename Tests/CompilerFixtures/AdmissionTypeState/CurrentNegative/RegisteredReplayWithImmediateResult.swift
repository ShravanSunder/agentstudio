func constructCurrentRegisteredReplayWithImmediateResult()
    -> OrderedFactReplayCompletion<Int, Int>
{
    let immediateResult = OrderedFactImmediateReplayResult.invalidated
    return .registered(immediateResult, wake: .scheduleDrain)
}
