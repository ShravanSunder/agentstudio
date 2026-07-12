func constructCurrentNonemptyOrdinaryGatherLease() -> GatherDrainLease<Int, Int> {
    let contribution = GatherContribution(
        key: 1,
        payload: 1,
        footprint: GatherFootprint(itemCount: 1, byteCount: 1),
        recoverySignal: .ordinary
    )
    return GatherDrainLease(
        token: makeCurrentGatherDrainToken(),
        key: 1,
        payload: .contributions(
            NonEmptyAdmissionBatch(first: contribution, remaining: [])
        )
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
