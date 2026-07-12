func constructEmptyOrdinaryGatherLease() -> GatherDrainLease<Int, Int> {
    GatherDrainLease(
        token: makeLegacyGatherDrainToken(),
        key: 1,
        contributions: [],
        recoveryRevision: nil
    )
}

private func makeLegacyGatherDrainToken() -> AdmissionDrainToken {
    AdmissionDrainToken(
        generation: AdmissionGeneration(owner: .runtimeFacts, value: 1),
        mailboxIdentity: AdmissionOpaqueIdentity(),
        bindingEpoch: AdmissionOpaqueIdentity(),
        bindingSequence: 1,
        leaseEpoch: AdmissionOpaqueIdentity(),
        leaseSequence: 1
    )
}
