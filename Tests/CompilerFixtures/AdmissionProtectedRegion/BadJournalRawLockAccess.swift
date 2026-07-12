func accessOrderedFactJournalRawLock(
    _ journal: OrderedFactJournal<Int, Int>
) -> UInt64 {
    journal.lock.withLock { state in
        state.latestSequence
    }
}
