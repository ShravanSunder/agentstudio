func constructCurrentOrderedDrainWithEmptyFacts() -> OrderedFactDrain<Int> {
    OrderedFactDrain(
        token: makeCurrentOrderedDrainToken(),
        payload: .facts([]),
        oldestRetainedAge: ExactAdmissionAge(duration: .zero)
    )
}

private func makeCurrentOrderedDrainToken() -> AdmissionDrainToken {
    AdmissionDrainToken(
        generation: AdmissionGeneration(owner: .runtimeFacts, value: 1),
        mailboxIdentity: AdmissionOpaqueIdentity(),
        bindingEpoch: AdmissionOpaqueIdentity(), bindingSequence: 1,
        leaseEpoch: AdmissionOpaqueIdentity(), leaseSequence: 1
    )
}
