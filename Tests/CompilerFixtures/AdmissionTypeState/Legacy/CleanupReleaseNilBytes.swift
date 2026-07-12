func constructCleanupReleaseWithNilBytes() -> AdmissionCleanupTurn {
    AdmissionCleanupTurn(
        releasedEntryCount: 1,
        releasedByteCount: nil,
        wake: .noWake
    )
}
