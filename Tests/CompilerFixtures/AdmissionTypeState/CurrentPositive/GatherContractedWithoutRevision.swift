func constructCurrentContractedGatherRevision() -> GatherAdmissionDisposition<Int> {
    .contractedToRecovery(
        GatherRecoveryRevision(
            generation: AdmissionGeneration(owner: .filesystemObservation, value: 1),
            key: 1,
            stamp: .sequenced(1)
        ),
        .capacityPressure
    )
}
