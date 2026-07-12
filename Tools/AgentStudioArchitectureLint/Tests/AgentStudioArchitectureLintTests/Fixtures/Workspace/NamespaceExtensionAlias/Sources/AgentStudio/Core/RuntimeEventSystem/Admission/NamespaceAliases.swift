enum Outer {
    enum Inner {
        typealias Handle<Fact, Snapshot> = OrderedFactJournal<Fact, Snapshot>
    }
}

typealias OuterAlias = Outer

enum UnrelatedOuter {
    enum Inner {
        typealias Handle<Fact, Snapshot> = String
    }
}

typealias UnrelatedOuterAlias = UnrelatedOuter
