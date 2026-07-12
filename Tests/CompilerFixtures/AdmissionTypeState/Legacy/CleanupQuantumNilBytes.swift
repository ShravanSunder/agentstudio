func constructCleanupQuantumWithNilBytes() -> AdmissionCleanupQuantum {
    AdmissionCleanupQuantum(
        maximumEntries: 1,
        maximumBytes: nil
    )
}
