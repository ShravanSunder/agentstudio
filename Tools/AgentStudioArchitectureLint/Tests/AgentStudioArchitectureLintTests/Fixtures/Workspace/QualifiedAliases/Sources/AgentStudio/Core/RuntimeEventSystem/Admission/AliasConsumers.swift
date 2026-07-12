func consumeUnrelatedHandle(
    handle: UnrelatedNamespace.Handle,
    token: borrowing AdmissionProtectedRegionToken
) {
    _ = handle
    _ = token
}

func consumeJournalHandle(
    handle: JournalNamespace.Handle<Int, String>,
    token: borrowing AdmissionProtectedRegionToken
) {
    _ = handle
    _ = token
}

func consumeAmbiguousHandle(
    handle: Handle,
    token: borrowing AdmissionProtectedRegionToken
) {
    _ = handle
    _ = token
}

extension UnrelatedNamespace {
    func consumeLocalHandle(
        handle: Handle,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        _ = handle
        _ = token
    }
}

extension JournalNamespace {
    func consumeLocalHandle(
        handle: Handle<Int, String>,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        _ = handle
        _ = token
    }
}
