func constructLatestMissingAgeDrain() -> LatestValueDrain<Int, Int> {
    LatestValueDrain(
        token: makeLegacyLatestDrainToken(),
        valuesByKey: [1: 1],
        oldestRetainedAge: nil
    )
}

private func makeLegacyLatestDrainToken() -> AdmissionDrainToken {
    AdmissionDrainToken(
        generation: AdmissionGeneration(owner: .terminalViewport, value: 1),
        mailboxIdentity: AdmissionOpaqueIdentity(),
        bindingEpoch: AdmissionOpaqueIdentity(),
        bindingSequence: 1,
        leaseEpoch: AdmissionOpaqueIdentity(),
        leaseSequence: 1
    )
}
