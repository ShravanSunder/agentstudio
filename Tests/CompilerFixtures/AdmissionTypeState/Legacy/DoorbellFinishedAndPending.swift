func constructDoorbellFinishedAndPending() -> AdmissionDoorbellStateSnapshot {
    AdmissionDoorbellStateSnapshot(
        hasPendingSignal: true,
        hasWaitingConsumer: false,
        isFinished: true
    )
}
