enum CanonicalNameShadow {
    typealias OrderedFactJournal<Fact, Snapshot> = String

    static func retainLocalValue(
        value: OrderedFactJournal<Int, String>,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        _ = value
        _ = token
    }
}
