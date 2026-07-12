func constructLatestEmptyDrain() -> LatestValueDrain<Int, Int> {
    LatestValueDrain(
        token: makeLegacyLatestDrainToken(),
        valuesByKey: [:],
        oldestRetainedAge: .exact(.zero)
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
