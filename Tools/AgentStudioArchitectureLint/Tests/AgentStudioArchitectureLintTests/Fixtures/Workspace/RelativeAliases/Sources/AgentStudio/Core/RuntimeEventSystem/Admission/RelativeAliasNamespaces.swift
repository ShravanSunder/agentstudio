enum Outer {
    enum JournalNamespace {
        typealias Base<Fact, Snapshot> = OrderedFactJournal<Fact, Snapshot>
    }

    enum UnrelatedNamespace {
        typealias Base<Fact, Snapshot> = String
    }
}

enum JournalNamespace {
    typealias Handle<Fact, Snapshot> = String
}

enum UnrelatedNamespace {
    typealias Handle<Fact, Snapshot> = OrderedFactJournal<Fact, Snapshot>
}
