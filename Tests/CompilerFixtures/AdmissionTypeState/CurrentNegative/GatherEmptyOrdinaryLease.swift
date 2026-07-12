func constructCurrentEmptyOrdinaryGatherLease() -> GatherDrainLease<Int, Int> {
    GatherDrainLease(
        token: makeCurrentGatherDrainToken(),
        key: 1,
        payload: GatherDrainPayload<Int, Int>.contributions([])
    )
}

private func makeCurrentGatherDrainToken() -> AdmissionDrainToken {
    AdmissionDrainToken(
        generation: AdmissionGeneration(owner: .filesystemObservation, value: 1),
        mailboxIdentity: AdmissionOpaqueIdentity(),
        bindingEpoch: AdmissionOpaqueIdentity(),
        bindingSequence: 1,
        leaseEpoch: AdmissionOpaqueIdentity(),
        leaseSequence: 1
    )
}
