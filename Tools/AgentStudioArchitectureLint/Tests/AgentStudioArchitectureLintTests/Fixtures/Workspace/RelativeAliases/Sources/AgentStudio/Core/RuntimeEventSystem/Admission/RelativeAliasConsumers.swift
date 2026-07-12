extension Outer {
    struct RelativeAliasConsumers {
        func consumeJournalHandle(
            handle: JournalNamespace.Handle<Int, String>,
            token: borrowing AdmissionProtectedRegionToken
        ) {
            _ = handle
            _ = token
        }

        func consumeUnrelatedHandle(
            handle: UnrelatedNamespace.Handle<Int, String>,
            token: borrowing AdmissionProtectedRegionToken
        ) {
            _ = handle
            _ = token
        }
    }
}
