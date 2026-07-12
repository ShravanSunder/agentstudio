func inspectSwitchScopes(value: Int) {
    switch value {
    case 0:
        typealias OrderedFactJournal<Fact, Snapshot> = String
        let localShadow: OrderedFactJournal<Int, String>? = nil
        _ = localShadow
    case 1:
        func consumeCanonicalJournal(
            journal: OrderedFactJournal<Int, String>,
            token: borrowing AdmissionProtectedRegionToken
        ) {
            _ = journal
            _ = token
        }
        consumeCanonicalJournal
    default:
        typealias LocalJournal<Fact, Snapshot> = OrderedFactJournal<Fact, Snapshot>
        func consumeSameCaseAlias(
            journal: LocalJournal<Int, String>,
            token: borrowing AdmissionProtectedRegionToken
        ) {
            _ = journal
            _ = token
        }
        consumeSameCaseAlias
    }
}

func inspectConditionalCompilationScopes() {
    #if BRANCH_SCOPE_LOCAL_SHADOW
        typealias OrderedFactJournal<Fact, Snapshot> = String
        let localShadow: OrderedFactJournal<Int, String>? = nil
        _ = localShadow
    #elseif BRANCH_SCOPE_CANONICAL_CONSUMER
        func consumeCanonicalJournal(
            journal: OrderedFactJournal<Int, String>,
            token: borrowing AdmissionProtectedRegionToken
        ) {
            _ = journal
            _ = token
        }
        consumeCanonicalJournal
    #else
        typealias LocalJournal<Fact, Snapshot> = OrderedFactJournal<Fact, Snapshot>
        func consumeSameClauseAlias(
            journal: LocalJournal<Int, String>,
            token: borrowing AdmissionProtectedRegionToken
        ) {
            _ = journal
            _ = token
        }
        consumeSameClauseAlias
    #endif
}
