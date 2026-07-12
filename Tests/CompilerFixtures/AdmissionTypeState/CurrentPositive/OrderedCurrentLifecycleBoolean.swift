func constructCurrentOrderedStateWithClosedLifecycle()
    -> OrderedFactCurrentStateResult<Int>
{
    .current(snapshot: nil, latestSequence: 0, lifecycle: .sealed)
}
