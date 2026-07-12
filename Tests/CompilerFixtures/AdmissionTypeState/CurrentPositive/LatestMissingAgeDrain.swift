func constructCurrentLatestDrainWithAge() -> LatestValueDrain<Int, Int> {
    LatestValueDrain(
        token: makeCurrentLatestDrainToken(),
        values: NonEmptyAdmissionBatch(
            first: LatestValueEntry(key: 1, value: 1),
            remaining: []
        ),
        oldestRetainedAge: ExactAdmissionAge(duration: .zero)
    )
}

private func makeCurrentLatestDrainToken() -> AdmissionDrainToken {
    AdmissionDrainToken(
        generation: AdmissionGeneration(owner: .terminalViewport, value: 1),
        mailboxIdentity: AdmissionOpaqueIdentity(),
        bindingEpoch: AdmissionOpaqueIdentity(),
        bindingSequence: 1,
        leaseEpoch: AdmissionOpaqueIdentity(),
        leaseSequence: 1
    )
}
