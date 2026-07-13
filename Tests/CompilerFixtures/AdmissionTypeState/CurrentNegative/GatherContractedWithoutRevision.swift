func omitCurrentGatherContractionCause() -> GatherAdmissionDisposition<Int> {
    let recoveryRevision = GatherRecoveryRevision(
        generation: AdmissionGeneration(owner: .filesystemObservation, value: 1),
        key: 1,
        stamp: .sequenced(1)
    )
    return .contractedToRecovery(recoveryRevision)
}
