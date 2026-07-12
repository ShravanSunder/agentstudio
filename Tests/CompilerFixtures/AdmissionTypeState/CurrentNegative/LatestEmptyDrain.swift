func constructCurrentLatestDrainWithEmptyValues() -> LatestValueDrain<Int, Int> {
    LatestValueDrain(
        token: makeCurrentLatestDrainToken(),
        values: [],
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
