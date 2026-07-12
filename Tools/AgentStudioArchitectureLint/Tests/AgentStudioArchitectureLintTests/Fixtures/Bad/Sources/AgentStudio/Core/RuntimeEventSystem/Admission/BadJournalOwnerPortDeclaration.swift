final class OrderedFactJournal<Fact, Snapshot> {
}

struct JournalProducerPort<Fact, Snapshot> {
    let journal: OrderedFactJournal<Fact, Snapshot>
}
