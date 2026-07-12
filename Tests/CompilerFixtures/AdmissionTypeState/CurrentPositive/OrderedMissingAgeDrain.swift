func constructCurrentOrderedDrainWithAge() -> OrderedFactDrain<Int> {
    OrderedFactDrain(
        token: makeCurrentOrderedDrainToken(),
        payload: .facts(
            NonEmptyAdmissionBatch(first: makeCurrentSequencedFact(), remaining: [])
        ),
        oldestRetainedAge: ExactAdmissionAge(duration: .zero)
    )
}

private func makeCurrentSequencedFact() -> SequencedFact<Int> {
    SequencedFact(generation: AdmissionGeneration(owner: .runtimeFacts, value: 1), sequence: 1, fact: 1)
}

private func makeCurrentOrderedDrainToken() -> AdmissionDrainToken {
    AdmissionDrainToken(
        generation: AdmissionGeneration(owner: .runtimeFacts, value: 1),
        mailboxIdentity: AdmissionOpaqueIdentity(), bindingEpoch: AdmissionOpaqueIdentity(),
        bindingSequence: 1, leaseEpoch: AdmissionOpaqueIdentity(), leaseSequence: 1
    )
}
