typealias GoodJournalAlias<Fact, Snapshot> = GoodJournalBaseAlias<Fact, Snapshot>

struct GoodJournalAliasConsumer<Fact, Snapshot> {
    let journal: GoodJournalAlias<Fact, Snapshot>
}
