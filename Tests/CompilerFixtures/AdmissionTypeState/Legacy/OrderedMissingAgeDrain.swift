func constructOrderedMissingAgeDrain() -> OrderedFactDrain<Int> {
    OrderedFactDrain(
        token: makeLegacyOrderedDrainToken(),
        payload: .facts([makeLegacySequencedFact()]),
        oldestRetainedAge: nil
    )
}

private func makeLegacySequencedFact() -> SequencedFact<Int> {
    SequencedFact(
        generation: AdmissionGeneration(owner: .runtimeFacts, value: 1),
        sequence: 1,
        fact: 1
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
