func constructCurrentEntryAndByteCleanupRelease() -> AdmissionCleanupTurn {
    AdmissionCleanupTurn(
        release: .entriesAndBytes(count: 1, bytes: 1),
        wake: .noWake
    )
}
