func constructCurrentJournalWithBundledSnapshotBytes()
    throws -> OrderedFactJournal<Int, Int>
{
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
        cleanupQuantum: .entriesAndBytes(maximumEntries: 4, maximumBytes: 1024),
        initialSnapshotReplacement: OrderedFactSnapshotReplacement(
            snapshot: 1,
            estimatedBytes: 1
        )
    )
}
