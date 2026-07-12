enum UnrelatedNamespace {
    typealias Handle = String
}

enum JournalNamespace {
    typealias Base<Fact, Snapshot> = OrderedFactJournal<Fact, Snapshot>
}
