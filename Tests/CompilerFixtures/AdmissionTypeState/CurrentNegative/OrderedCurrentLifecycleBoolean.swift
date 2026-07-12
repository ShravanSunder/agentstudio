func constructCurrentOrderedStateWithBooleanLifecycle()
    -> OrderedFactCurrentStateResult<Int>
{
    .current(snapshot: nil, latestSequence: 0, lifecycle: true)
}
