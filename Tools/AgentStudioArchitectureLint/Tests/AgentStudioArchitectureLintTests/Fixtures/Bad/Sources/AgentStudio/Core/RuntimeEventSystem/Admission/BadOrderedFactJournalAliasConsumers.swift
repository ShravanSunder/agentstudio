typealias CrossFileJournalAlias<Fact, Snapshot> = CrossFileJournalBaseAlias<Fact, Snapshot>

typealias EscapedJournalState = CrossFileJournalAlias<Int, String>.State

func consumeJournalAuthority(
    journal: CrossFileJournalAlias<Int, String>,
    token: borrowing AdmissionProtectedRegionToken
) {
    _ = journal
    _ = token
}

let escapedJournalAuthority: (CrossFileJournalAlias<Int, String>, AdmissionProtectedRegionToken)? = nil
