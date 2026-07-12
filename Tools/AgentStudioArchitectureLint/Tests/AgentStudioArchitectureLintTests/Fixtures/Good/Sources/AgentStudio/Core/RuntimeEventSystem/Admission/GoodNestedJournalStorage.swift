struct GoodNestedJournalStorage {
    let journal: OrderedFactJournal<Int, String>

    struct ChildStorage {
        let journal: OrderedFactJournal<Int, String>
    }
}
