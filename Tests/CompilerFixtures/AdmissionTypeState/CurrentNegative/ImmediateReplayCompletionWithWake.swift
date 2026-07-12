func attachWakeToCurrentImmediateReplay()
    -> OrderedFactReplayCompletion<Int, Int>
{
    .immediate(.invalidated, wake: .scheduleDrain)
}
