func constructOrderedEmptyFactDrain() -> OrderedFactDrain<Int> {
    OrderedFactDrain(
        token: makeLegacyOrderedDrainToken(),
        payload: .facts([]),
        oldestRetainedAge: .exact(.zero)
    )
}

private func makeLegacyOrderedDrainToken() -> AdmissionDrainToken {
    AdmissionDrainToken(
        generation: AdmissionGeneration(owner: .runtimeFacts, value: 1),
        mailboxIdentity: AdmissionOpaqueIdentity(),
        bindingEpoch: AdmissionOpaqueIdentity(),
        bindingSequence: 1,
        leaseEpoch: AdmissionOpaqueIdentity(),
        leaseSequence: 1
    )
}
