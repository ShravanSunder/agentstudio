func constructJournalWithSplitInitialSnapshot() throws -> OrderedFactJournal<Int, Int> {
    try OrderedFactJournal(
        generation: AdmissionGeneration(owner: .runtimeFacts, value: 1),
        maximumRetainedFacts: 8,
        maximumRetainedBytes: 8192,
        snapshotLimits: OrderedFactSnapshotLimits(
            maximumSnapshotBytes: 1024,
            maximumPhysicalSnapshotCount: 2,
            maximumPhysicalSnapshotBytes: 2048
        ),
        maximumDrainFacts: 4,
        cleanupQuantum: AdmissionCleanupQuantum(
            maximumEntries: 4,
            maximumBytes: 1024
        ),
        initialSnapshot: nil,
        initialSnapshotBytes: 1
    )
}
